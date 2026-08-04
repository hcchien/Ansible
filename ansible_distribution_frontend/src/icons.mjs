/* ─────────────────────────────────────────────
   ELIX ICONS — the design's line-icon set.
   Geometry is taken verbatim from the symbol sprite in
   design/Elix/Elix Web.html so the web matches the mockups.
   Strokes inherit currentColor; sizes are the design's.
   ───────────────────────────────────────────── */

const STROKE = 'stroke="currentColor" fill="none" stroke-linecap="round" stroke-linejoin="round"';

const ICONS = {
  home: {
    box: '0 0 20 20',
    body: `<path d="M3 10 l7 -7 7 7 v7 h-5 v-5 h-4 v5 h-5 z" ${STROKE} stroke-width="1.4"/>`,
  },
  search: {
    box: '0 0 20 20',
    body: `<circle cx="9" cy="9" r="5.5" ${STROKE} stroke-width="1.5"/><path d="M13 13 l4 4" ${STROKE} stroke-width="1.5"/>`,
  },
  bell: {
    box: '0 0 20 20',
    body: `<path d="M5 14 v-4 a5 5 0 0 1 10 0 v4 l1.5 2 h-13 z M8 17 a2 2 0 0 0 4 0" ${STROKE} stroke-width="1.3"/>`,
  },
  circle: {
    box: '0 0 20 20',
    body: `<circle cx="10" cy="10" r="7" ${STROKE} stroke-width="1.3"/><circle cx="10" cy="10" r="2.4" fill="currentColor"/>`,
  },
  board: {
    box: '0 0 20 20',
    body: `<rect x="3.5" y="4" width="13" height="12" rx="2" ${STROKE} stroke-width="1.3"/><path d="M3.5 8 h13 M8 8 v8" ${STROKE} stroke-width="1.3"/>`,
  },
  eye: {
    box: '0 0 20 20',
    body: `<path d="M2 10 c 3 -5 13 -5 16 0 c -3 5 -13 5 -16 0 z" ${STROKE} stroke-width="1.3"/><circle cx="10" cy="10" r="2.6" ${STROKE} stroke-width="1.3"/>`,
  },
  plus: {
    box: '0 0 20 20',
    body: `<path d="M10 4 v12 M4 10 h12" ${STROKE} stroke-width="1.8"/>`,
  },
  chev: {
    box: '0 0 20 20',
    body: `<path d="M8 5 l5 5 -5 5" ${STROKE} stroke-width="1.5"/>`,
  },
  heart: {
    box: '0 0 22 22',
    body: `<path d="M11 19 C 2.5 13 2 7.5 5.8 6 C 8.4 5 11 7.5 11 7.5 C 11 7.5 13.6 5 16.2 6 C 20 7.5 19.5 13 11 19 Z" ${STROKE} stroke-width="1.5"/>`,
  },
  comment: {
    box: '0 0 22 22',
    body: `<path d="M3.5 6 a2 2 0 0 1 2 -2 h11 a2 2 0 0 1 2 2 v7 a2 2 0 0 1 -2 2 h-6 l-4 3 v-3 h-1 a2 2 0 0 1 -2 -2 z" ${STROKE} stroke-width="1.5"/>`,
  },
  repost: {
    box: '0 0 22 22',
    body: `<path d="M5 9 V7.5 A2 2 0 0 1 7 5.5 H15 M12.5 3 L15.5 5.5 L12.5 8 M17 13 V14.5 A2 2 0 0 1 15 16.5 H7 M9.5 19 L6.5 16.5 L9.5 14" ${STROKE} stroke-width="1.5"/>`,
  },
  share: {
    box: '0 0 22 22',
    body: `<path d="M19 3 L9.5 12.5 M19 3 L13 19 L9.5 12.5 L3 9 Z" ${STROKE} stroke-width="1.5"/>`,
  },
  person: {
    box: '0 0 24 24',
    body: `<circle cx="12" cy="8.5" r="3.5" ${STROKE} stroke-width="1.5"/><path d="M5.5 19 a6.5 6.5 0 0 1 13 0" ${STROKE} stroke-width="1.5"/>`,
  },
  wallet: {
    box: '0 0 20 20',
    body: `<circle cx="10" cy="10" r="6.5" ${STROKE} stroke-width="1.3"/><circle cx="10" cy="10" r="2.4" ${STROKE} stroke-width="1.3"/>`,
  },
  sync: {
    box: '0 0 20 20',
    body: `<path d="M4 8 a6 6 0 0 1 10 -2 l2 -2 M16 12 a6 6 0 0 1 -10 2 l-2 2" ${STROKE} stroke-width="1.4"/><path d="M14 4 l2 2 -2 2 M6 16 l-2 -2 2 -2" ${STROKE} stroke-width="1.4"/>`,
  },
  lang: {
    box: '0 0 20 20',
    body: `<path d="M3 6 h8 M7 4 v2 M5 6 c 0 4 2 6 5 7 M9 6 c 0 4 -2 6 -5 7 M10 16 l3 -7 3 7 M11.2 13.5 h3.6" ${STROKE} stroke-width="1.3"/>`,
  },
  finger: {
    box: '0 0 20 20',
    body: `<path d="M5 11 a5 5 0 0 1 10 0 M7 11 a3 3 0 0 1 6 0 v3 M10 11 v4 M4 8 a7 7 0 0 1 12 0" ${STROKE} stroke-width="1.2"/>`,
  },
  read: {
    box: '0 0 20 20',
    body: `<path d="M3 5 h14 v10 h-14 z M3 5 l7 5 7 -5" ${STROKE} stroke-width="1.3"/>`,
  },
  write: {
    box: '0 0 20 20',
    body: `<path d="M4 14 l9 -9 3 3 -9 9 h-3 z M11 7 l3 3" ${STROKE} stroke-width="1.3"/>`,
  },
  qr: {
    box: '0 0 24 24',
    body: `<path d="M4 4 h6 v6 h-6 z M14 4 h6 v6 h-6 z M4 14 h6 v6 h-6 z M14 14 h2 v2 h-2 z M18 14 h2 v2 h-2 z M14 18 h2 v2 h-2 z M18 18 h2 v2 h-2 z" ${STROKE} stroke-width="1.4"/>`,
  },
};

/// Inline SVG for [name] at [size] px. Unknown names render nothing so a
/// typo degrades to a missing glyph rather than a broken page.
export function icon(name, size = 20, className = 'elix-icon') {
  const spec = ICONS[name];
  if (!spec) return '';
  return `<svg class="${className}" width="${size}" height="${size}" viewBox="${spec.box}" aria-hidden="true" focusable="false">${spec.body}</svg>`;
}

/// The signed seal that sits beside a handle — a filled rosette with a
/// knocked-out check. Always accent-colored by its container.
export function sealIcon(size = 14) {
  return `<span class="seal"><svg width="${size}" height="${size}" viewBox="0 0 16 16" aria-hidden="true" focusable="false"><path d="M8 1.5 l1.6 1.2 2 -.2 .6 1.9 1.7 1.1 -.7 1.9 .7 1.9 -1.7 1.1 -.6 1.9 -2 -.2 -1.6 1.2 -1.6 -1.2 -2 .2 -.6 -1.9 -1.7 -1.1 .7 -1.9 -.7 -1.9 1.7 -1.1 .6 -1.9 2 .2 z" fill="currentColor"/><path d="M5.6 8 l1.6 1.6 3.2 -3.4" stroke="var(--surface)" stroke-width="1.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg></span>`;
}

export function hasIcon(name) {
  return Object.hasOwn(ICONS, name);
}
