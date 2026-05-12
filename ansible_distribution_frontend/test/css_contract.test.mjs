import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const css = await readFile(
  new URL('../src/styles.css', import.meta.url),
  'utf8',
);

assert.match(
  css,
  /\[hidden\]\s*\{[^}]*display:\s*none\s*!important;/s,
  'hidden elements must stay hidden even when component classes define display',
);
assert.match(
  css,
  /--background:\s*#faf6ec;/,
  'Elix paper background token is required',
);
assert.match(
  css,
  /--surface-raised:\s*#f0ebda;/,
  'Elix raised paper token is required',
);
assert.match(
  css,
  /--surface-deep:\s*#e8e1cf;/,
  'Elix deep paper token is required',
);
assert.match(
  css,
  /--border:\s*#d9d2be;/,
  'Elix rule token is required',
);
assert.match(
  css,
  /--muted-fill:\s*#e8e1cf;/,
  'Elix muted fill token is required',
);
assert.match(
  css,
  /--accent:\s*#b97a3c;/,
  'Elix amber accent token is required',
);
assert.match(
  css,
  /--warning:\s*#7a3e1e;/,
  'Elix ember warning token is required',
);
assert.match(
  css,
  /--danger:\s*#7a3e1e;/,
  'Elix danger token is required',
);
assert.match(
  css,
  /--success:\s*#4a6b5e;/,
  'Elix sage success token is required',
);
assert.match(
  css,
  /--text:\s*#1a1815;/,
  'Elix ink token is required',
);
assert.match(
  css,
  /--muted:\s*#3a3530;/,
  'Elix soft ink token is required',
);
assert.match(
  css,
  /\.elix-mark\s*\{[^}]*width:\s*34px;/s,
  'Elix constellation mark must be present',
);
assert.match(
  css,
  /\.command-header\s*\{[^}]*display:\s*grid;/s,
  'command header must be a stable grid',
);
assert.match(
  css,
  /\.card\s*\{[^}]*display:\s*flex;[^}]*flex-direction:\s*column;/s,
  'Elix cards must provide the shared component container model',
);
assert.match(
  css,
  /\.board-head\s*\{[^}]*grid-template-columns:\s*1fr auto auto;/s,
  'board detail must use the Elix board-head hierarchy on desktop',
);
assert.match(
  css,
  /\.login-grid\s*\{[^}]*grid-template-columns:\s*1\.15fr 1fr;/s,
  'login page must use the Elix challenge and QR split layout on desktop',
);
assert.match(
  css,
  /\.qr-preview\s*\{[^}]*grid-template-columns:\s*repeat\(12,\s*1fr\);/s,
  'login challenge must include a code-native QR preview grid',
);
assert.match(
  css,
  /\.mobile-tabbar\s*\{[^}]*display:\s*none;/s,
  'mobile tab bar should stay hidden on desktop',
);
assert.match(
  css,
  /@media\s*\(max-width:\s*560px\)[\s\S]*\.mobile-tabbar\s*\{[^}]*display:\s*flex;/,
  'mobile breakpoint must reveal the Elix tab bar',
);
assert.match(
  css,
  /\.focus-visible\s*,\s*button:focus-visible\s*,\s*a:focus-visible\s*\{/,
  'focus-visible class must share the focus outline treatment',
);
assert.match(
  css,
  /\.session-chip\s*\{[^}]*white-space:\s*nowrap;/s,
  'session chip text must not wrap',
);
assert.match(
  css,
  /@media\s*\(max-width:\s*900px\)/,
  'mobile breakpoint is required',
);
assert.doesNotMatch(
  css,
  /border-radius:\s*(1[2-9]|[2-9][0-9])px/,
  'cards and panels must not use oversized radii',
);
const backgroundDeclarations = css
  .split(';')
  .map((declaration) => declaration.trim())
  .filter(Boolean);
assert.equal(
  backgroundDeclarations.find((declaration) =>
    /background(?:-image)?\s*:[^;]*(?:linear-gradient|radial-gradient|conic-gradient)\(/i.test(
      declaration,
    ),
  ),
  undefined,
  'Elix UI must not rely on decorative background gradients',
);

console.log('ok - hidden elements stay hidden');
