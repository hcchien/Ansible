import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';

import { createFrontendServer } from '../server.mjs';
import {
  LEGAL_PAGE_PATHS,
  PRIVACY_CONTACT_EMAIL,
  SUPPORT_CONTACT_EMAIL,
  renderLegalPage,
  resolveLegalLocale,
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
    '/support',
    '/account-deletion',
    '/child-safety',
  ]);
  assert.equal(resolveLegalLocale('en-US,en;q=0.9'), 'en');
  assert.equal(resolveLegalLocale('fr-FR, en;q=0.8'), 'fr');
  assert.equal(resolveLegalLocale('zh-TW, en;q=0.5'), 'zh-Hant');
  assert.equal(resolveLegalLocale('ja-JP'), 'ja');
  assert.match(
    renderLegalPage('/terms', { locale: 'fr-FR, en;q=0.8' }).html,
    /<html lang="en">/,
  );
  assert.equal(renderLegalPage('/no-such-page'), null);
  assert.equal(renderLegalPage('/privacy/').html, renderLegalPage('/privacy').html);
  assert.match(renderLegalPage('/privacy').html, /保存期間/); // retention table
  assert.match(renderLegalPage('/privacy').html, /append-only/);
  assert.match(renderLegalPage('/privacy', { locale: 'en' }).html, /<html lang="en">/);
  assert.match(renderLegalPage('/privacy', { locale: 'en' }).html, /Privacy Policy/);
  assert.doesNotMatch(renderLegalPage('/privacy', { locale: 'en' }).html, /隱私權政策/);
  assert.doesNotMatch(renderLegalPage('/privacy', { locale: 'en' }).html, /<section id="en"/);

  const privacyExpectations = {
    en: ['Privacy Policy', 'Applicable law'],
    'zh-Hant': ['隱私權政策', '法規適用'],
    fr: ['Politique de confidentialité', 'Droit applicable'],
    es: ['Política de privacidad', 'Legislación aplicable'],
    ja: ['プライバシーポリシー', '適用法令'],
    ko: ['개인정보 처리방침', '적용 법률'],
    de: ['Datenschutzerklärung', 'Anwendbares Recht'],
    it: ['Informativa sulla privacy', 'Legge applicabile'],
  };

  for (const [locale, needles] of Object.entries(privacyExpectations)) {
    const html = renderLegalPage('/privacy', { locale }).html;
    assert.match(html, new RegExp(`<html lang="${locale}">`));
    for (const needle of needles) assert.ok(html.includes(needle), `${locale} must contain ${needle}`);
    assert.equal((html.match(/<h2>/g) ?? []).length, 9, `${locale} must contain every policy section`);
    const retentionBody = html.match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1] ?? '';
    assert.equal((retentionBody.match(/<tr>/g) ?? []).length, 11, `${locale} must contain every retention row`);
    assert.match(html, new RegExp(`href="/account-deletion\\?lang=${locale}"`));
    for (const availableLocale of Object.keys(privacyExpectations)) {
      assert.match(html, new RegExp(`href="/privacy\\?lang=${availableLocale}"`));
    }
  }

  // --- each legal route is a real server-rendered page (no JS required) ------
  const zhExpectations = {
    '/privacy': ['隱私權政策', '個人資料保護法', 'GDPR'],
    '/terms': ['服務條款', '中華民國（台灣）'],
    '/about': ['關於 Elix'],
    '/support': ['Elix 支援中心', SUPPORT_CONTACT_EMAIL, '回報問題'],
    '/account-deletion': [
      '刪除帳號與資料',
      '清除本機身分',
    ],
    '/child-safety': ['兒少安全標準', '零容忍', SUPPORT_CONTACT_EMAIL],
  };
  const enExpectations = {
    '/privacy': ['Privacy Policy', 'Personal Data Protection Act', 'GDPR'],
    '/terms': ['Terms of Service', 'Republic of China (Taiwan)'],
    '/about': ['About Elix', 'self-sovereign identity'],
    '/support': ['Elix Support', SUPPORT_CONTACT_EMAIL, 'reporting a problem'],
    '/account-deletion': ['Account &amp; Data Deletion', 'Clear local identity'],
    '/child-safety': ['Child Safety Standards', 'zero tolerance', SUPPORT_CONTACT_EMAIL],
  };

  for (const path of LEGAL_PAGE_PATHS) {
    const zhPage = await request(`${baseUrl}${path}`, {
      headers: { 'accept-language': 'zh-TW,zh;q=0.9,en;q=0.5' },
    });
    assert.equal(zhPage.status, 200, `${path} must be served`);
    assert.match(zhPage.headers['content-type'], /text\/html/);
    for (const needle of zhExpectations[path]) {
      assert.ok(zhPage.body.includes(needle), `${path} must contain ${needle}`);
    }
    assert.match(zhPage.body, /<html lang="zh-Hant">/);
    assert.doesNotMatch(zhPage.body, /<section id="en" lang="en">/);
    assert.match(zhPage.body, new RegExp(`href="${path.replace('/', '\\/') + '\\?lang=en'}"`));
    assert.doesNotMatch(zhPage.body, /href="\/(?:privacy|terms|about|support|account-deletion|child-safety)"/);

    const enPage = await request(`${baseUrl}${path}`, {
      headers: { 'accept-language': 'en-US,en;q=0.9,zh-TW;q=0.5' },
    });
    assert.equal(enPage.status, 200, `${path} must be served in English`);
    assert.match(enPage.headers['content-type'], /text\/html/);
    for (const needle of enExpectations[path]) {
      assert.ok(enPage.body.includes(needle), `${path} must contain English ${needle}`);
    }
    assert.match(enPage.body, /<html lang="en">/);
    assert.doesNotMatch(enPage.body, /<section id="en" lang="en">/);
    assert.match(enPage.body, new RegExp(`href="${path.replace('/', '\\/') + '\\?lang=zh-Hant'}"`));
    assert.doesNotMatch(enPage.body, /href="\/(?:privacy|terms|about|support|account-deletion|child-safety)"/);

    // Footer: effective date + privacy contact.
    assert.ok(zhPage.body.includes('2026-07-07'), `${path} must show effective date`);
    assert.ok(zhPage.body.includes(PRIVACY_CONTACT_EMAIL), `${path} must show contact`);
    assert.ok(enPage.body.includes('2026-07-07'), `${path} must show effective date`);
    assert.ok(enPage.body.includes(PRIVACY_CONTACT_EMAIL), `${path} must show contact`);
    // Header links back home and across legal pages.
    assert.match(zhPage.body, /<a class="legal-home" href="\/\?lang=zh-Hant">Elix<\/a>/);
    assert.match(zhPage.body, /href="\/terms\?lang=zh-Hant"/);
    assert.match(enPage.body, /<a class="legal-home" href="\/\?lang=en">Elix<\/a>/);
    assert.match(enPage.body, /href="\/terms\?lang=en"/);
    // No SPA boot script — the page must work without JS.
    assert.ok(!zhPage.body.includes('src/main.mjs'), `${path} must not boot the SPA`);
    assert.ok(!enPage.body.includes('src/main.mjs'), `${path} must not boot the SPA`);
  }

  // Explicit query language wins over Accept-Language for links emitted by the SPA.
  const queryLocale = await request(`${baseUrl}/privacy?lang=en`, {
    headers: { 'accept-language': 'zh-TW,zh;q=0.9' },
  });
  assert.match(queryLocale.body, /<html lang="en">/);
  assert.match(queryLocale.body, /Privacy Policy/);
  assert.doesNotMatch(queryLocale.body, /隱私權政策/);

  for (const [locale, needles] of Object.entries(privacyExpectations)) {
    const localizedPage = await request(`${baseUrl}/privacy?lang=${locale}`, {
      headers: { 'accept-language': 'zh-TW,zh;q=0.9' },
    });
    assert.equal(localizedPage.status, 200, `${locale} privacy page must be served`);
    assert.match(localizedPage.body, new RegExp(`<html lang="${locale}">`));
    for (const needle of needles) {
      assert.ok(localizedPage.body.includes(needle), `${locale} server page must contain ${needle}`);
    }
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
