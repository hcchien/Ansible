import { DEFAULT_LOCALE, resolveLocale } from './web_i18n.mjs';

const RELAY_BASE_URL_KEY = 'trisaura.relay_base_url';
const LOCALE_KEY = 'trisaura.locale';

export function resolveFrontendRuntimeConfig({
  location = globalThis.location,
  storage = globalThis.localStorage,
  navigatorLike = globalThis.navigator,
} = {}) {
  const locationUrl = toLocationUrl(location);
  const storedRelayBaseUrl = storage?.getItem?.(RELAY_BASE_URL_KEY);
  const runtimeRelayOrigin = runtimeConfiguredRelayOrigin();
  const fallbackRelayOrigin = runtimeRelayOrigin ?? defaultRelayOrigin(locationUrl);
  const relayOrigin =
    runtimeRelayOrigin ??
    normalizeLocalRelayBaseUrl(storedRelayBaseUrl ?? fallbackRelayOrigin, fallbackRelayOrigin, {
      pageOrigin: locationUrl.origin,
    });
  const relayBaseUrl = shouldUseSameOriginRelayProxy(locationUrl, relayOrigin)
    ? locationUrl.origin
    : relayOrigin;

  return {
    relayBaseUrl,
    relayOrigin,
    webOrigin: locationUrl.origin,
    locale: resolveLocale(
      locationUrl.searchParams.get('lang') ?? storage?.getItem?.(LOCALE_KEY) ?? navigatorLike?.language ?? DEFAULT_LOCALE,
    ),
  };
}

function runtimeConfiguredRelayOrigin() {
  const value = globalThis.__ELIX_RUNTIME_CONFIG__?.relayOrigin;
  if (typeof value !== 'string' || value.trim() === '') return null;

  try {
    const url = new URL(value);
    if (url.protocol === 'https:' && url.hostname) return url.origin;
    if (url.protocol === 'http:' && isLoopbackHost(url.hostname)) {
      return normalizeLocalRelayBaseUrl(url.origin);
    }
  } catch {
    return null;
  }

  return null;
}

export function defaultRelayOrigin(location) {
  const locationUrl = toLocationUrl(location);
  if (isLocalFrontendServer(locationUrl)) {
    return `${locationUrl.protocol}//localhost:4001`;
  }

  return locationUrl.origin;
}

// Optional build-time allowlist of extra HTTPS relay hosts (comma-separated).
// Injected at build time via a global; empty in dev. Defense-in-depth: without
// this, a stored `trisaura.relay_base_url` could point browser API traffic at
// any HTTPS host an attacker controls.
const ALLOWED_RELAY_HOSTS = String(globalThis.__ELIX_ALLOWED_RELAY_HOSTS__ ?? '')
  .split(',')
  .map((host) => host.trim().toLowerCase())
  .filter(Boolean);

export function normalizeLocalRelayBaseUrl(
  value,
  fallbackValue = 'http://localhost:4001',
  { pageOrigin } = {},
) {
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol)) {
      return fallbackValue;
    }
    // Plain HTTP is only allowed to loopback (development). Plain HTTP to a
    // non-loopback host would route browser API traffic over an untrusted
    // cleartext channel and is rejected.
    if (url.protocol === 'http:' && !isLoopbackHost(url.hostname)) {
      return fallbackValue;
    }
    if (url.protocol === 'http:' && isLoopbackHost(url.hostname) && url.port === '4001') {
      return 'http://localhost:4001';
    }
    // HTTPS is restricted to the page's own origin host (the common
    // same-origin/subdomain proxy deployment) or an explicit build-time
    // allowlist. Any other HTTPS host — e.g. an attacker-planted value in
    // localStorage — falls back to the default rather than being trusted.
    if (url.protocol === 'https:' && !isAllowedHttpsRelayHost(url.hostname, pageOrigin)) {
      return fallbackValue;
    }
    return trimTrailingSlash(url.toString());
  } catch {
    return fallbackValue;
  }
}

function isAllowedHttpsRelayHost(hostname, pageOrigin) {
  const host = hostname.toLowerCase();
  if (ALLOWED_RELAY_HOSTS.includes(host)) return true;
  if (!pageOrigin) return false;
  try {
    const pageHost = new URL(pageOrigin).hostname.toLowerCase();
    // Same host, or a subdomain of the page host (e.g. relay.example under
    // web.example is NOT matched, but api.web.example under web.example is;
    // keep it strict — exact host or a subdomain of the page host).
    return host === pageHost || host.endsWith(`.${pageHost}`);
  } catch {
    return false;
  }
}

function shouldUseSameOriginRelayProxy(locationUrl, relayOrigin) {
  if (locationUrl.protocol === 'https:') return true;
  if (!isLocalFrontendServer(locationUrl)) return false;

  try {
    const relayUrl = new URL(relayOrigin);
    return relayUrl.protocol === 'http:' && isLoopbackHost(relayUrl.hostname) && relayUrl.port === '4001';
  } catch {
    return false;
  }
}

function isLocalFrontendServer(locationUrl) {
  return locationUrl.protocol === 'http:' && isLoopbackHost(locationUrl.hostname) && locationUrl.port === '5173';
}

function isLoopbackHost(hostname) {
  return hostname === 'localhost' || hostname === '127.0.0.1';
}

function toLocationUrl(location) {
  if (location instanceof URL) return location;
  return new URL(location?.href ?? String(location));
}

function trimTrailingSlash(value) {
  return String(value).replace(/\/+$/, '');
}
