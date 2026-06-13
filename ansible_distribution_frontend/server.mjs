import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { createServer as createHttpServer, request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { dirname, extname, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  buildPageMetadata,
  injectMetaTags,
  parseSharePath,
  renderMetaTags,
  resolveOrigin,
} from './src/og_meta.mjs';

const DEFAULT_PORT = 5173;
const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_RELAY_BASE_URL = 'http://localhost:4001';
const SERVER_ROOT = dirname(fileURLToPath(import.meta.url));

// Observability baseline (service architecture plan, Phase 0 — closes G17).
// A dependency-free Prometheus counter set: prom-client would be the idiomatic
// choice, but the frontend ships with zero runtime deps, so a tiny hand-rolled
// registry keeps it that way while emitting standard Prometheus exposition.
//
// Exposed series (served at GET /metrics):
//   frontend_requests_total{kind}            — requests by kind (asset/proxy/health/metrics)
//   frontend_upstream_requests_total         — relay calls attempted via the proxy
//   frontend_upstream_errors_total{reason}   — relay calls that failed (transport/5xx)
function createMetrics() {
  const counters = {
    frontend_requests_total: {
      help: 'Frontend HTTP requests by kind.',
      label: 'kind',
      values: new Map(),
    },
    frontend_upstream_requests_total: {
      help: 'Upstream relay calls attempted via the proxy.',
      label: null,
      values: new Map(),
    },
    frontend_upstream_errors_total: {
      help: 'Upstream relay calls that failed, by reason.',
      label: 'reason',
      values: new Map(),
    },
  };

  function inc(name, labelValue = '') {
    const counter = counters[name];
    if (!counter) return;
    counter.values.set(labelValue, (counter.values.get(labelValue) ?? 0) + 1);
  }

  function render() {
    let out = '';
    for (const [name, counter] of Object.entries(counters)) {
      out += `# HELP ${name} ${counter.help}\n# TYPE ${name} counter\n`;
      if (counter.values.size === 0) {
        // Emit at zero so the series is discoverable before the first event.
        out += `${name} 0\n`;
        continue;
      }
      for (const key of [...counter.values.keys()].sort()) {
        const value = counter.values.get(key);
        if (counter.label && key !== '') {
          out += `${name}{${counter.label}="${escapeLabel(key)}"} ${value}\n`;
        } else {
          out += `${name} ${value}\n`;
        }
      }
    }
    return out;
  }

  return { inc, render };
}

function escapeLabel(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
}

// Module-level singleton: shared across all servers created in-process.
const metrics = createMetrics();

export { metrics };

const MIME_TYPES = Object.freeze({
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
});

// Security headers applied to every response served by this frontend server.
const SECURITY_HEADERS = Object.freeze({
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'strict-origin-when-cross-origin',
  // CSP: same-origin scripts only; no inline scripts; no plugins; no framing.
  // The frontend is a plain ES-module SPA with no inline event handlers or
  // eval usage, so this policy is safe to enforce without nonces.
  'content-security-policy': [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data:",
    "connect-src 'self'",
    "font-src 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join('; '),
});

const HOP_BY_HOP_HEADERS = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

export function createFrontendServer({
  rootDir = SERVER_ROOT,
  relayBaseUrl = process.env.RELAY_BASE_URL ?? DEFAULT_RELAY_BASE_URL,
  logger = console,
} = {}) {
  const resolvedRoot = resolve(rootDir);
  const resolvedRelayBaseUrl = normalizeRelayProxyBaseUrl(relayBaseUrl);

  return createHttpServer((request, response) => {
    handleRequest(request, response, {
      rootDir: resolvedRoot,
      relayBaseUrl: resolvedRelayBaseUrl,
      logger,
    }).catch((error) => {
      logger?.error?.(error);
      sendJson(response, 500, { error: 'frontend_server_error' });
    });
  });
}

export function startFrontendServer({
  host = process.env.HOST ?? DEFAULT_HOST,
  port = Number(process.env.PORT ?? DEFAULT_PORT),
  relayBaseUrl = process.env.RELAY_BASE_URL ?? DEFAULT_RELAY_BASE_URL,
  rootDir = SERVER_ROOT,
  logger = console,
} = {}) {
  const server = createFrontendServer({ rootDir, relayBaseUrl, logger });

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      logger?.log?.(
        `Elix web frontend listening on http://${host}:${server.address().port} -> ${trimTrailingSlash(relayBaseUrl)}`,
      );
      resolve(server);
    });
  });
}

async function handleRequest(request, response, context) {
  const url = new URL(request.url ?? '/', 'http://frontend.local');

  if (url.pathname === '/metrics') {
    // Phase 0 — observability baseline. Deliberately not counted as a request
    // so scrapes do not inflate frontend_requests_total.
    response.writeHead(200, {
      ...SECURITY_HEADERS,
      'content-type': 'text/plain; version=0.0.4; charset=utf-8',
      'cache-control': 'no-store',
    });
    response.end(metrics.render());
    return;
  }

  if (url.pathname === '/healthz') {
    // Do not include relayBaseUrl in the response — it reveals internal service
    // topology (host, port) to any caller that can reach this endpoint.
    metrics.inc('frontend_requests_total', 'health');
    sendJson(response, 200, {
      ok: true,
      service: 'elix-web-frontend',
    });
    return;
  }

  if (url.pathname.startsWith('/api/')) {
    metrics.inc('frontend_requests_total', 'proxy');
    await proxyRelayRequest(request, response, url, context);
    return;
  }

  // Outbound sharing loop (PM review finding #2): board/thread pages are served
  // with per-page Open Graph + Twitter Card meta tags so a pasted link renders
  // a rich preview in LINE / Threads / Messenger and pulls visitors back in.
  const sharePath = parseSharePath(url.pathname);
  if (sharePath && ['GET', 'HEAD'].includes(request.method ?? 'GET')) {
    metrics.inc('frontend_requests_total', 'share');
    await serveSharePage(request, response, sharePath, context);
    return;
  }

  metrics.inc('frontend_requests_total', 'asset');
  await serveFrontendAsset(request, response, url, context);
}

// Serves the SPA index.html with per-page OG/Twitter meta injected into the
// <head>. Board metadata is sourced from the relay's public boards list; a
// relay failure degrades gracefully to origin-only canonical tags rather than
// taking the page down (the SPA still boots for human visitors regardless).
async function serveSharePage(request, response, sharePath, context) {
  const { rootDir, relayBaseUrl } = context;
  let html;
  try {
    html = await readFile(resolve(rootDir, 'index.html'), 'utf8');
  } catch {
    // No index.html to enrich — fall back to the normal asset/SPA path.
    await serveFrontendAsset(request, response, new URL(request.url ?? '/', 'http://frontend.local'), context);
    return;
  }

  const origin = resolveOrigin(request);
  const boards = await fetchPublicBoards(relayBaseUrl);
  const metadata = buildPageMetadata(sharePath, { boards, origin });
  const headTags = renderMetaTags(metadata);
  const document = injectMetaTags(html, headTags);
  const body = Buffer.from(document, 'utf8');

  response.writeHead(200, {
    ...SECURITY_HEADERS,
    'content-type': 'text/html; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-store',
  });
  response.end(request.method === 'HEAD' ? undefined : body);
}

// Fetches the relay's public boards list (same endpoint the SPA uses) for
// board title/description. Uses node http/https directly (the frontend ships
// with zero runtime deps and targets Node < 18, where global fetch is absent),
// returning [] on any failure so meta injection never blocks page delivery.
function fetchPublicBoards(relayBaseUrl) {
  return new Promise((resolvePromise) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      resolvePromise(value);
    };

    let relayUrl;
    try {
      relayUrl = new URL('/api/v1/forum-host/boards', `${trimTrailingSlash(relayBaseUrl)}/`);
    } catch {
      finish([]);
      return;
    }

    const requestFn = relayUrl.protocol === 'https:' ? httpsRequest : httpRequest;
    const relayRequest = requestFn(
      relayUrl,
      { method: 'GET', headers: { accept: 'application/json' } },
      (relayResponse) => {
        if ((relayResponse.statusCode ?? 500) >= 400) {
          relayResponse.resume();
          finish([]);
          return;
        }
        let raw = '';
        relayResponse.setEncoding('utf8');
        relayResponse.on('data', (chunk) => {
          raw += chunk;
        });
        relayResponse.on('end', () => {
          try {
            const payload = JSON.parse(raw);
            finish(
              (payload?.boards ?? []).map((board) => ({
                id: board?.hosted_board_id ?? '',
                slug: board?.slug ?? board?.hosted_board_id ?? '',
                title: board?.title ?? '',
                description: board?.description ?? '',
              })),
            );
          } catch {
            finish([]);
          }
        });
      },
    );

    relayRequest.on('error', () => finish([]));
    relayRequest.setTimeout(2000, () => {
      relayRequest.destroy();
      finish([]);
    });
    relayRequest.end();
  });
}

async function serveFrontendAsset(request, response, url, { rootDir }) {
  if (!['GET', 'HEAD'].includes(request.method ?? 'GET')) {
    response.writeHead(405, { ...SECURITY_HEADERS, allow: 'GET, HEAD' });
    response.end();
    return;
  }

  const pathname = safeDecodePath(url.pathname);
  const requestedPath = pathname === '/' ? '/index.html' : pathname;
  const filePath = resolve(rootDir, `.${requestedPath}`);

  if (!isPathInside(filePath, rootDir)) {
    response.writeHead(403, { ...SECURITY_HEADERS, 'content-type': 'text/plain; charset=utf-8' });
    response.end('Forbidden');
    return;
  }

  const resolvedFilePath = await resolveStaticFile(filePath, rootDir, pathname);
  if (!resolvedFilePath) {
    response.writeHead(404, { ...SECURITY_HEADERS, 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }

  await streamFile(response, resolvedFilePath, request.method === 'HEAD');
}

async function resolveStaticFile(filePath, rootDir, pathname) {
  try {
    const fileStat = await stat(filePath);
    if (fileStat.isFile()) return filePath;
  } catch {
    // Fall through to SPA fallback.
  }

  if (!extname(pathname)) {
    return resolve(rootDir, 'index.html');
  }

  return null;
}

async function streamFile(response, filePath, headOnly) {
  const fileStat = await stat(filePath);
  response.writeHead(200, {
    ...SECURITY_HEADERS,
    'content-type': MIME_TYPES[extname(filePath)] ?? 'application/octet-stream',
    'content-length': fileStat.size,
    'cache-control': 'no-store',
  });

  if (headOnly) {
    response.end();
    return;
  }

  await new Promise((resolvePromise, reject) => {
    createReadStream(filePath)
      .once('error', reject)
      .once('end', resolvePromise)
      .pipe(response);
  });
}

function proxyRelayRequest(clientRequest, clientResponse, url, { relayBaseUrl }) {
  return new Promise((resolvePromise) => {
    const relayUrl = new URL(`${url.pathname}${url.search}`, relayBaseUrl);
    const requestFn = relayUrl.protocol === 'https:' ? httpsRequest : httpRequest;
    const headers = filterProxyHeaders(clientRequest.headers);
    headers.host = relayUrl.host;

    metrics.inc('frontend_upstream_requests_total');

    const relayRequest = requestFn(
      relayUrl,
      {
        method: clientRequest.method,
        headers,
      },
      (relayResponse) => {
        const status = relayResponse.statusCode ?? 502;
        if (status >= 500) {
          metrics.inc('frontend_upstream_errors_total', 'upstream_5xx');
        }
        // Merge security headers last so they cannot be overridden by relay.
        const proxiedHeaders = {
          ...filterProxyHeaders(relayResponse.headers),
          ...SECURITY_HEADERS,
        };
        clientResponse.writeHead(status, proxiedHeaders);
        relayResponse.pipe(clientResponse);
        relayResponse.on('end', resolvePromise);
      },
    );

    relayRequest.on('error', () => {
      metrics.inc('frontend_upstream_errors_total', 'transport');
      sendJson(clientResponse, 502, { error: 'relay_unavailable' });
      resolvePromise();
    });

    clientRequest.pipe(relayRequest);
  });
}

function filterProxyHeaders(headers) {
  return Object.fromEntries(
    Object.entries(headers).filter(([name]) => !HOP_BY_HOP_HEADERS.has(name.toLowerCase())),
  );
}

function sendJson(response, status, body) {
  const json = JSON.stringify(body);
  response.writeHead(status, {
    ...SECURITY_HEADERS,
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(json),
    'cache-control': 'no-store',
  });
  response.end(json);
}

function safeDecodePath(pathname) {
  try {
    return decodeURIComponent(pathname);
  } catch {
    return '/';
  }
}

function isPathInside(filePath, rootDir) {
  const normalizedRoot = rootDir.endsWith(sep) ? rootDir : `${rootDir}${sep}`;
  return filePath === rootDir || filePath.startsWith(normalizedRoot);
}

function trimTrailingSlash(value) {
  return String(value).replace(/\/+$/, '');
}

function normalizeRelayProxyBaseUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === 'http:' && url.hostname === 'localhost' && url.port === '4001') {
      url.hostname = '127.0.0.1';
    }
    return trimTrailingSlash(url.toString());
  } catch {
    return trimTrailingSlash(value);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  startFrontendServer();
}
