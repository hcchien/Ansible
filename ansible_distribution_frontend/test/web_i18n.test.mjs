import assert from 'node:assert/strict';

import {
  DEFAULT_LOCALE,
  SUPPORTED_LOCALES,
  getTranslationKeys,
  resolveLocale,
  t,
} from '../src/web_i18n.mjs';

assert.equal(DEFAULT_LOCALE, 'zh-Hant');
assert.deepEqual(SUPPORTED_LOCALES, ['en', 'zh-Hant']);
assert.equal(resolveLocale('zh-TW'), 'zh-Hant');
assert.equal(resolveLocale('zh-Hant-TW'), 'zh-Hant');
assert.equal(resolveLocale('en-US'), 'en');
assert.equal(resolveLocale('fr-FR'), 'zh-Hant');
assert.equal(t('login.title', {}, 'zh-Hant'), '用 Elix app 登入');
assert.equal(t('login.title', {}, 'en'), 'App login challenge');
assert.equal(t('common.boardCount', { count: 2 }, 'zh-Hant'), '2 個看板');

const baselineKeys = getTranslationKeys('zh-Hant');
for (const locale of SUPPORTED_LOCALES) {
  assert.deepEqual(getTranslationKeys(locale), baselineKeys, `${locale} translation keys must match zh-Hant`);
}

console.log('ok - web i18n');
