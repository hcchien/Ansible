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
  'command header must keep the stable grid shell',
);
assert.match(
  css,
  /\.cols\s*\{[^}]*grid-template-columns:\s*260px minmax\(0,\s*1fr\) 300px;/s,
  'Elix web home must use the three-column social layout',
);
assert.match(
  css,
  /\.rail,\s*\.right-rail\s*\{[^}]*align-self:\s*start;/s,
  'side rails must align to the top of the central wall',
);
assert.doesNotMatch(
  css,
  /\.rail,\s*\.right-rail\s*\{[^}]*top:\s*96px;/s,
  'side rails should not use a sticky offset that creates top misalignment',
);
assert.match(
  css,
  /\.feed\s*\{[^}]*display:\s*flex;[^}]*flex-direction:\s*column;/s,
  'feed column must provide a stable vertical post stack',
);
assert.match(
  css,
  /\.compose\s*\{[^}]*padding:\s*14px;/s,
  'compose card must be present for Note and Murmur posting',
);
assert.match(
  css,
  /\.post\s*\{[^}]*display:\s*flex;[^}]*flex-direction:\s*column;/s,
  'post cards must provide the shared feed item model',
);
assert.match(
  css,
  /\.forum-main\s*\{[^}]*width:\s*100%;[^}]*overflow-x:\s*hidden;/s,
  'main surface must stay within the viewport',
);
assert.match(
  css,
  /\.login-grid\s*\{[^}]*grid-template-columns:\s*1\.15fr 1fr;/s,
  'login page must use the Elix challenge and QR split layout on desktop',
);
assert.match(
  css,
  /\.challenge-payload-preview span\s*\{[^}]*overflow-wrap:\s*anywhere;/s,
  'login challenge instruction copy must stay readable beside the QR',
);
assert.match(
  css,
  /\.qr-code\s*\{[^}]*shape-rendering:\s*crispEdges;/s,
  'login challenge QR must render as crisp SVG modules',
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
