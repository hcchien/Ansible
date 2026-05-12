import assert from 'node:assert/strict';

import { renderQrCodeSvg } from '../src/qr_code.mjs';

const payload =
  'trisaura://web-session/approve?challenge_id=wsc_fixture&relay_origin=http%3A%2F%2Flocalhost%3A4001';
const svg = renderQrCodeSvg(payload);

assert.match(svg, /class="qr-code"/);
assert.match(svg, /viewBox="0 0 57 57"/);
assert.match(svg, /<rect x="4" y="4" width="1" height="1"\/>/);
assert.doesNotMatch(svg, /trisaura:\/\/web-session/);

assert.throws(
  () => renderQrCodeSvg('x'.repeat(155)),
  /QR payload is too large/,
);

console.log('ok - renders local SVG QR code');
