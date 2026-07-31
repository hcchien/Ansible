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
  /--background:\s*#ffffff;/,
  'Elix Web daylight background token is required',
);
assert.match(
  css,
  /--surface:\s*#ffffff;/,
  'Elix Web white card surface token is required',
);
assert.match(
  css,
  /--surface-raised:\s*#f7f8fc;/,
  'Elix Web daylight raised surface token is required',
);
assert.match(
  css,
  /--surface-deep:\s*#eef1f9;/,
  'Elix Web daylight deep surface token is required',
);
assert.match(
  css,
  /--border:\s*#dfe3ee;/,
  'Elix Web daylight rule token is required',
);
assert.match(
  css,
  /--muted-fill:\s*#eef1f9;/,
  'Elix Web daylight muted fill token is required',
);
assert.match(
  css,
  /--accent:\s*#2550af;/,
  'Elix cobalt accent token is required',
);
assert.match(
  css,
  /--lavender:\s*#c7b7f9;/,
  'Elix lavender signal token is required',
);
assert.match(
  css,
  /--highlight:\s*#eee500;/,
  'Elix citron highlight token is required',
);
assert.match(
  css,
  /--warning:\s*#a86b00;/,
  'Elix daylight warning token is required',
);
assert.match(
  css,
  /--danger:\s*#cc3b2e;/,
  'Elix daylight danger token is required',
);
assert.match(
  css,
  /--success:\s*#17845c;/,
  'Elix daylight success token is required',
);
assert.match(
  css,
  /--text:\s*#191919;/,
  'Elix Web daylight text token is required',
);
assert.match(
  css,
  /--muted:\s*#55607a;/,
  'Elix Web daylight muted text token is required',
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
  /\.mobile-focus-stage\s*\{[^}]*display:\s*grid;/s,
  'mobile focus scene switcher must be implemented as a real app surface',
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
  /\.board-thread-row\s*\{[^}]*display:\s*grid;/s,
  'board thread rows must use the Elix Web thread list layout',
);
assert.match(
  css,
  /\.thread-hd\s*\{[^}]*border-bottom:\s*1px solid var\(--border\);/s,
  'thread detail must have the Elix Web thread header rule',
);
assert.match(
  css,
  /\.thread-op\s*\{[^}]*display:\s*grid;/s,
  'original post must use the Threads-style post grid',
);
assert.match(
  css,
  /\.thread-reply-item\s*\{[^}]*display:\s*grid;/s,
  'replies must render as full conversation items instead of blank left-border blocks',
);
assert.match(
  css,
  /\.thread-reply-item:not\(:last-child\)::after\s*\{/,
  'reply items must draw a conversation connector line',
);
assert.match(
  css,
  /\.thread-reply-composer\s*\{[^}]*display:\s*grid;/s,
  'thread detail must include the inline reply composer surface',
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
  /@media\s*\(max-width:\s*560px\)[\s\S]*\.forum-shell\[data-page-id="home"\]\s+\.mobile-tabbar\s*\{[^}]*display:\s*none;/,
  'mobile focus home must not show the legacy tab bar over the swipe scene',
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
  /border-radius:\s*(2[1-9]|[3-9][0-9])px/,
  'cards and panels must not use oversized radii (paper sheets cap at 20px)',
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
