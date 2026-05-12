import assert from 'node:assert/strict';

import { resolveFrontendRuntimeConfig } from '../src/runtime_config.mjs';

const localConfig = resolveFrontendRuntimeConfig({
  location: new URL('http://127.0.0.1:5173/#/login'),
  storage: createStorage(),
  navigatorLike: { language: 'zh-TW' },
});
assert.equal(localConfig.webOrigin, 'http://127.0.0.1:5173');
assert.equal(localConfig.relayOrigin, 'http://localhost:4001');
assert.equal(localConfig.relayBaseUrl, 'http://127.0.0.1:5173');
assert.equal(localConfig.locale, 'zh-Hant');

const storedLoopbackConfig = resolveFrontendRuntimeConfig({
  location: new URL('http://localhost:5173/#/login'),
  storage: createStorage([['trisaura.relay_base_url', 'http://127.0.0.1:4001']]),
  navigatorLike: { language: 'en-US' },
});
assert.equal(storedLoopbackConfig.relayOrigin, 'http://localhost:4001');
assert.equal(storedLoopbackConfig.relayBaseUrl, 'http://localhost:5173');
assert.equal(storedLoopbackConfig.locale, 'en');

const invalidStoredRelayConfig = resolveFrontendRuntimeConfig({
  location: new URL('http://127.0.0.1:5173/#/login'),
  storage: createStorage([['trisaura.relay_base_url', 'localhost:4001']]),
  navigatorLike: { language: 'zh-TW' },
});
assert.equal(invalidStoredRelayConfig.relayOrigin, 'http://localhost:4001');
assert.equal(invalidStoredRelayConfig.relayBaseUrl, 'http://127.0.0.1:5173');

const customRelayConfig = resolveFrontendRuntimeConfig({
  location: new URL('https://web.elix.example/#/login'),
  storage: createStorage([['trisaura.relay_base_url', 'https://relay.elix.example']]),
  navigatorLike: { language: 'ja-JP' },
});
assert.equal(customRelayConfig.webOrigin, 'https://web.elix.example');
assert.equal(customRelayConfig.relayOrigin, 'https://relay.elix.example');
assert.equal(customRelayConfig.relayBaseUrl, 'https://relay.elix.example');
assert.equal(customRelayConfig.locale, 'zh-Hant');

console.log('ok - runtime config');

function createStorage(entries = []) {
  const values = new Map(entries);
  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
  };
}
