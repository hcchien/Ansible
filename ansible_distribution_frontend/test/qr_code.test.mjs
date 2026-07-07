import assert from 'node:assert/strict';

import { renderQrCodeSvg } from '../src/qr_code.mjs';

const payload =
  'trisaura://web-session/approve?challenge_id=wsc_fixture&relay_origin=http%3A%2F%2Flocalhost%3A4001';
const svg = renderQrCodeSvg(payload);
const moduleRects = [
  ...svg.matchAll(/<rect x="\d+" y="\d+" width="1" height="1"\/>/g),
];

assert.match(svg, /class="qr-code"/);
assert.match(svg, /viewBox="0 0 57 57"/);
assert.match(svg, /class="qr-code__background"[^>]*fill="#fff"/);
assert.match(svg, /class="qr-code__modules"[^>]*fill="#000"/);
assert.equal(moduleRects.length, 1218);
assert.match(svg, /<rect x="4" y="4" width="1" height="1"\/>/);
assert.match(
  svg,
  /<rect x="5" y="10" width="1" height="1"\/>/,
  'top-left finder bottom border must not be overwritten by timing pattern',
);
assert.match(
  svg,
  /<rect x="10" y="5" width="1" height="1"\/>/,
  'top-left finder right border must not be overwritten by timing pattern',
);
assert.doesNotMatch(svg, /trisaura:\/\/web-session/);

assert.throws(
  () => renderQrCodeSvg('x'.repeat(155)),
  /QR payload is too large/,
);

console.log('ok - renders local SVG QR code');
