// Server-side Open Graph + Twitter Card meta tag injection.
//
// The frontend is a hash-routed ES-module SPA: the same static index.html is
// served for every path and the client paints the page from `location.hash`.
// Social crawlers (LINE / Threads / Messenger / Slack) do not run JS and ignore
// the fragment, so a pasted board/thread link renders as a naked URL with no
// preview — the outbound sharing loop the PM review (finding #2) flagged as
// missing.
//
// This module closes that gap on the server: for the public, path-based
// board and thread URLs it injects per-page <meta property="og:*"> /
// <meta name="twitter:*"> tags and a <link rel="canonical"> into the served
// HTML <head>, so the crawler sees a real title/description/url. The SPA still
// boots normally for human visitors (the body and script tag are untouched).
//
// Path grammar (path-based, crawler-visible — distinct from the in-app
// `#/boards/:id` hash routes):
//   /boards/:boardId                          → board page  (og:type=website)
//   /boards/:boardId/threads/:threadId        → thread page (og:type=article)

const SITE_NAME = 'Elix';
const MAX_DESCRIPTION_LENGTH = 160;

// Escapes a value for safe interpolation into HTML text/attribute contexts.
// Mirrors the canonical escape in forum_shell_renderer.mjs; kept local so the
// server does not pull in the i18n/render module chain just to escape a string.
export function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// Parses a request pathname into the share-page descriptor, or null when the
// path is not a board/thread page (the server then serves the SPA unchanged).
export function parseSharePath(pathname) {
  const segments = decodeSegments(pathname);

  if (segments.length === 2 && segments[0] === 'boards') {
    return { kind: 'board', boardId: segments[1] };
  }

  if (
    segments.length === 4 &&
    segments[0] === 'boards' &&
    segments[2] === 'threads'
  ) {
    return {
      kind: 'thread',
      boardId: segments[1],
      threadId: segments[3],
    };
  }

  return null;
}

function decodeSegments(pathname) {
  return String(pathname ?? '')
    .split('/')
    .filter(Boolean)
    .map((segment) => {
      try {
        return decodeURIComponent(segment);
      } catch {
        return segment;
      }
    });
}

// Strips HTML, collapses whitespace, and truncates to ~160 chars for use as an
// og:description / twitter:description. Returns '' for empty input.
export function buildDescription(raw, maxLength = MAX_DESCRIPTION_LENGTH) {
  const text = String(raw ?? '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1).trimEnd()}…`;
}

// Resolves the absolute origin (scheme://host) this request was served on, so
// canonical/og:url match the URL the crawler actually fetched. Honours the
// PUBLIC_BASE_URL env override first (the deployment's canonical origin), then
// forwarded headers, then the Host header. Returns null when no trustworthy
// origin can be derived (caller then omits absolute URLs rather than fabricate).
export function resolveOrigin(request, { publicBaseUrl = process.env.PUBLIC_BASE_URL } = {}) {
  if (publicBaseUrl) {
    const normalized = normalizeOrigin(publicBaseUrl);
    if (normalized) return normalized;
  }

  const headers = request?.headers ?? {};
  const forwardedHost = firstHeaderValue(headers['x-forwarded-host']);
  const host = forwardedHost || firstHeaderValue(headers.host);
  if (!host) return null;

  const forwardedProto = firstHeaderValue(headers['x-forwarded-proto']);
  const proto = (forwardedProto || (request?.socket?.encrypted ? 'https' : 'http')).toLowerCase();
  if (!/^[a-z][a-z0-9+.-]*$/.test(proto)) return null;

  return normalizeOrigin(`${proto}://${host}`);
}

function firstHeaderValue(value) {
  if (Array.isArray(value)) return value[0]?.split(',')[0]?.trim() ?? '';
  return String(value ?? '').split(',')[0].trim();
}

function normalizeOrigin(value) {
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol)) return null;
    return `${url.protocol}//${url.host}`;
  } catch {
    return null;
  }
}

// Builds the page metadata (title/description/type/canonicalUrl) for a share
// page from the descriptor + the boards already known to the relay. Thread
// pages reuse the board title/description as the excerpt source — the relay has
// no per-thread content endpoint yet, so the board is the best available
// context (see TODO below). `boards` is the normalized board list, or [].
export function buildPageMetadata(descriptor, { boards = [], origin = null } = {}) {
  const board = findBoard(boards, descriptor.boardId);

  if (descriptor.kind === 'board') {
    const title = (board?.title || descriptor.boardId).trim() || descriptor.boardId;
    return {
      title: `${title} · ${SITE_NAME}`,
      description: buildDescription(board?.description) || defaultBoardDescription(title),
      type: 'website',
      canonicalUrl: absoluteUrl(origin, `/boards/${encodeURIComponent(descriptor.boardId)}`),
    };
  }

  // Thread page. TODO(relay thread endpoint): once the relay exposes per-thread
  // title/excerpt, fetch and use it here for a thread-specific preview. Until
  // then the board provides the title/description context, with the thread id
  // making the canonical URL unique.
  const boardTitle = (board?.title || descriptor.boardId).trim() || descriptor.boardId;
  return {
    title: `${boardTitle} · ${SITE_NAME}`,
    description: buildDescription(board?.description) || defaultBoardDescription(boardTitle),
    type: 'article',
    canonicalUrl: absoluteUrl(
      origin,
      `/boards/${encodeURIComponent(descriptor.boardId)}/threads/${encodeURIComponent(descriptor.threadId)}`,
    ),
  };
}

function defaultBoardDescription(title) {
  return `${title} on ${SITE_NAME} — 沒有機器人、沒有真名、內容永遠是你的討論區。`;
}

function findBoard(boards, boardId) {
  return (boards ?? []).find(
    (candidate) => candidate?.id === boardId || candidate?.slug === boardId,
  );
}

function absoluteUrl(origin, path) {
  if (!origin) return null;
  return `${origin}${path}`;
}

// Renders the <head> meta/link tags for the page. All interpolated values are
// HTML-escaped. og:image is omitted when no per-content image exists and no
// static site default is configured (OG_DEFAULT_IMAGE) — the review forbids
// fabricating one.
export function renderMetaTags(metadata, { defaultImage = process.env.OG_DEFAULT_IMAGE } = {}) {
  const tags = [];
  const title = escapeHtml(metadata.title);
  const description = escapeHtml(metadata.description);

  tags.push(`<title>${title}</title>`);
  if (metadata.description) {
    tags.push(`<meta name="description" content="${description}" />`);
  }
  if (metadata.canonicalUrl) {
    tags.push(`<link rel="canonical" href="${escapeHtml(metadata.canonicalUrl)}" />`);
  }

  tags.push(`<meta property="og:site_name" content="${escapeHtml(SITE_NAME)}" />`);
  tags.push(`<meta property="og:type" content="${escapeHtml(metadata.type)}" />`);
  tags.push(`<meta property="og:title" content="${title}" />`);
  if (metadata.description) {
    tags.push(`<meta property="og:description" content="${description}" />`);
  }
  if (metadata.canonicalUrl) {
    tags.push(`<meta property="og:url" content="${escapeHtml(metadata.canonicalUrl)}" />`);
  }

  tags.push(`<meta name="twitter:card" content="summary" />`);
  tags.push(`<meta name="twitter:title" content="${title}" />`);
  if (metadata.description) {
    tags.push(`<meta name="twitter:description" content="${description}" />`);
  }

  const image = metadata.image || defaultImage;
  if (image) {
    const escapedImage = escapeHtml(image);
    tags.push(`<meta property="og:image" content="${escapedImage}" />`);
    tags.push(`<meta name="twitter:image" content="${escapedImage}" />`);
    tags.push(`<meta name="twitter:card" content="summary_large_image" />`);
  }

  return tags.join('\n    ');
}

// Injects rendered head tags into an index.html document, replacing the static
// <title> placeholder. Returns the original html unchanged if no <head> is
// found (defensive — the SPA still boots).
export function injectMetaTags(html, headTags) {
  const withoutPlaceholderTitle = html.replace(/<title>[^<]*<\/title>\s*/i, '');
  const headClose = withoutPlaceholderTitle.indexOf('</head>');
  if (headClose === -1) return html;

  return (
    withoutPlaceholderTitle.slice(0, headClose) +
    `    ${headTags}\n  ` +
    withoutPlaceholderTitle.slice(headClose)
  );
}

export const SHARE_META = Object.freeze({ SITE_NAME, MAX_DESCRIPTION_LENGTH });
