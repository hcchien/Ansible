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
  /--background:\s*#0f1720;/,
  'network console background token is required',
);
assert.match(
  css,
  /--header:\s*#101c27;/,
  'network console header token is required',
);
assert.match(
  css,
  /--surface:\s*#142230;/,
  'network console surface token is required',
);
assert.match(
  css,
  /--border:\s*#253646;/,
  'network console border token is required',
);
assert.match(
  css,
  /--muted-fill:\s*#31505b;/,
  'network console muted fill token is required',
);
assert.match(
  css,
  /--accent:\s*#7dd3c7;/,
  'network console accent token is required',
);
assert.match(
  css,
  /--warning:\s*#f2c14e;/,
  'network console warning token is required',
);
assert.match(
  css,
  /--danger:\s*#f97066;/,
  'network console danger token is required',
);
assert.match(
  css,
  /--text:\s*#dce7e5;/,
  'network console text token is required',
);
assert.match(
  css,
  /--muted:\s*#93a4ad;/,
  'network console muted token is required',
);
assert.match(
  css,
  /\.command-header\s*\{[^}]*display:\s*grid;/s,
  'command header must be a stable grid',
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
  'network console UI must not rely on decorative background gradients',
);

console.log('ok - hidden elements stay hidden');
