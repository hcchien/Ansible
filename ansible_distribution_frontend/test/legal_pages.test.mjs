import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';

import { createFrontendServer } from '../server.mjs';
import {
  LEGAL_PAGE_PATHS,
  PRIVACY_CONTACT_EMAIL,
  renderLegalPage,
} from '../src/legal_pages.mjs';

// Legal pages never touch the relay/appview upstreams, so point them at a
// closed port to prove that (any accidental upstream call would fail loudly).
const frontend = createFrontendServer({
  relayBaseUrl: 'http://127.0.0.1:9',
  appViewBaseUrl: 'http://127.0.0.1:9',
  logger: null,
});
await listen(frontend);
const baseUrl = `http://127.0.0.1:${frontend.address().port}`;

try {
  // --- module-level contract -------------------------------------------------
  assert.deepEqual(LEGAL_PAGE_PATHS, [
    '/privacy',
    '/terms',
    '/about',
    '/account-deletion',
  ]);
  assert.equal(renderLegalPage('/no-such-page'), null);
  assert.equal(renderLegalPage('/privacy/'), renderLegalPage('/privacy'));
  assert.match(renderLegalPage('/privacy').html, /保存期間/); // retention table
  assert.match(renderLegalPage('/privacy').html, /append-only/);

  // --- each legal route is a real server-rendered page (no JS required) ------
  const expectations = {
    '/privacy': ['隱私權政策', 'Privacy Policy', '個人資料保護法', 'GDPR'],
    '/terms': ['服務條款', 'Terms of Service', '中華民國（台灣）'],
    '/about': ['關於 Elix', 'About Elix'],
    '/account-deletion': [
      '刪除帳號與資料',
      'Account &amp; Data Deletion',
      '清除本機身分',
    ],
  };

  for (const path of LEGAL_PAGE_PATHS) {
    const page = await request(`${baseUrl}${path}`);
    assert.equal(page.status, 200, `${path} must be served`);
    assert.match(page.headers['content-type'], /text\/html/);
    for (const needle of expectations[path]) {
      assert.ok(page.body.includes(needle), `${path} must contain ${needle}`);
    }
    // Bilingual single page: zh-Hant document with an #en anchor section.
    assert.match(page.body, /<html lang="zh-Hant">/);
    assert.match(page.body, /<section id="en" lang="en">/);
    // Footer: effective date + privacy contact.
    assert.ok(page.body.includes('2026-07-07'), `${path} must show effective date`);
    assert.ok(page.body.includes(PRIVACY_CONTACT_EMAIL), `${path} must show contact`);
    // Header links back home and across legal pages.
    assert.match(page.body, /<a class="legal-home" href="\/">Elix<\/a>/);
    assert.match(page.body, /href="\/terms"/);
    // No SPA boot script — the page must work without JS.
    assert.ok(!page.body.includes('src/main.mjs'), `${path} must not boot the SPA`);
  }

  // Trailing slash tolerated (store consoles / reviewers paste both forms).
  const slashed = await request(`${baseUrl}/privacy/`);
  assert.equal(slashed.status, 200);

  // HEAD works (some store validators use it).
  const head = await request(`${baseUrl}/privacy`, { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(head.body, '');

  // Non-GET methods are not accepted for legal pages.
  const post = await request(`${baseUrl}/privacy`, { method: 'POST' });
  assert.equal(post.status, 405);

  // --- surrounding routing is unaffected --------------------------------------
  // Unknown extensionful path still 404s.
  const missing = await request(`${baseUrl}/no-such-file.png`);
  assert.equal(missing.status, 404);

  // A non-legal extensionless path still falls back to the SPA.
  const spa = await request(`${baseUrl}/privacy-center`);
  assert.equal(spa.status, 200);
  assert.match(spa.body, /src\/main.mjs/);

  // The legal stylesheet is a servable static asset (CSP allows only 'self').
  const css = await request(`${baseUrl}/src/legal.css`);
  assert.equal(css.status, 200);
  assert.match(css.headers['content-type'], /text\/css/);
} finally {
  await close(frontend);
}

console.log('ok - legal pages');

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
}

function close(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
}

function request(url, options = {}) {
  return new Promise((resolve, reject) => {
    const clientRequest = httpRequest(url, options, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        body += chunk;
      });
      response.on('end', () => {
        resolve({ status: response.statusCode, headers: response.headers, body });
      });
    });
    clientRequest.on('error', reject);
    clientRequest.end(options.body);
  });
}
