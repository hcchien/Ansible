import assert from 'node:assert/strict';

import { resolveFrontendRuntimeConfig, normalizeLocalRelayBaseUrl } from '../src/runtime_config.mjs';

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

const queryLocaleConfig = resolveFrontendRuntimeConfig({
  location: new URL('http://localhost:5173/?lang=en#/login'),
  storage: createStorage([['trisaura.locale', 'zh-Hant']]),
  navigatorLike: { language: 'zh-TW' },
});
assert.equal(queryLocaleConfig.locale, 'en');

const invalidStoredRelayConfig = resolveFrontendRuntimeConfig({
  location: new URL('http://127.0.0.1:5173/#/login'),
  storage: createStorage([['trisaura.relay_base_url', 'localhost:4001']]),
  navigatorLike: { language: 'zh-TW' },
});
assert.equal(invalidStoredRelayConfig.relayOrigin, 'http://localhost:4001');
assert.equal(invalidStoredRelayConfig.relayBaseUrl, 'http://127.0.0.1:5173');

// An HTTPS relay on the page's own host (or a subdomain of it) is trusted.
const sameHostRelayConfig = resolveFrontendRuntimeConfig({
  location: new URL('https://web.elix.example/#/login'),
  storage: createStorage([['trisaura.relay_base_url', 'https://web.elix.example']]),
  navigatorLike: { language: 'ja-JP' },
});
assert.equal(sameHostRelayConfig.webOrigin, 'https://web.elix.example');
assert.equal(sameHostRelayConfig.relayOrigin, 'https://web.elix.example');
assert.equal(sameHostRelayConfig.relayBaseUrl, 'https://web.elix.example');
assert.equal(sameHostRelayConfig.locale, 'zh-Hant');

const subdomainRelayConfig = resolveFrontendRuntimeConfig({
  location: new URL('https://web.elix.example/#/login'),
  storage: createStorage([['trisaura.relay_base_url', 'https://api.web.elix.example']]),
  navigatorLike: { language: 'en-US' },
});
assert.equal(subdomainRelayConfig.relayOrigin, 'https://api.web.elix.example');

const previousRuntimeConfig = globalThis.__ELIX_RUNTIME_CONFIG__;
globalThis.__ELIX_RUNTIME_CONFIG__ = {
  relayOrigin: 'https://relay-dev.elix.cool',
};
try {
  const deployedConfig = resolveFrontendRuntimeConfig({
    location: new URL('https://dev.elix.cool/#/login'),
    storage: createStorage(),
    navigatorLike: { language: 'zh-TW' },
  });
  assert.equal(deployedConfig.webOrigin, 'https://dev.elix.cool');
  assert.equal(deployedConfig.relayOrigin, 'https://relay-dev.elix.cool');
  assert.equal(deployedConfig.relayBaseUrl, 'https://dev.elix.cool');
} finally {
  if (previousRuntimeConfig === undefined) {
    delete globalThis.__ELIX_RUNTIME_CONFIG__;
  } else {
    globalThis.__ELIX_RUNTIME_CONFIG__ = previousRuntimeConfig;
  }
}

// Security: plain HTTP to a non-loopback host must be rejected because browser
// API traffic would cross an untrusted cleartext channel.
assert.equal(
  normalizeLocalRelayBaseUrl('http://attacker.example/evil'),
  'http://localhost:4001',
  'non-loopback HTTP relay URL must fall back to default',
);

// Security (defense-in-depth): an HTTPS relay host that is neither the page's
// own host nor an allowlisted host must NOT be trusted from localStorage.
assert.equal(
  normalizeLocalRelayBaseUrl('https://attacker.example', 'http://localhost:4001', {
    pageOrigin: 'https://web.elix.example',
  }),
  'http://localhost:4001',
  'unrelated HTTPS relay host must fall back to default',
);
assert.equal(
  normalizeLocalRelayBaseUrl('https://web.elix.example', 'http://localhost:4001', {
    pageOrigin: 'https://web.elix.example',
  }),
  'https://web.elix.example',
  'same-host HTTPS relay must be accepted',
);

console.log('ok - runtime config');

function createStorage(entries = []) {
  const values = new Map(entries);
  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
  };
}
