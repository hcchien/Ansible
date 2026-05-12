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
  const fallbackRelayOrigin = defaultRelayOrigin(locationUrl);
  const relayOrigin = normalizeLocalRelayBaseUrl(storedRelayBaseUrl ?? fallbackRelayOrigin, fallbackRelayOrigin);
  const relayBaseUrl = shouldUseSameOriginRelayProxy(locationUrl, relayOrigin)
    ? locationUrl.origin
    : relayOrigin;

  return {
    relayBaseUrl,
    relayOrigin,
    webOrigin: locationUrl.origin,
    locale: resolveLocale(storage?.getItem?.(LOCALE_KEY) ?? navigatorLike?.language ?? DEFAULT_LOCALE),
  };
}

export function defaultRelayOrigin(location) {
  const locationUrl = toLocationUrl(location);
  if (isLocalFrontendServer(locationUrl)) {
    return `${locationUrl.protocol}//localhost:4001`;
  }

  return locationUrl.origin;
}

export function normalizeLocalRelayBaseUrl(value, fallbackValue = 'http://localhost:4001') {
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol)) {
      return fallbackValue;
    }
    if (url.protocol === 'http:' && isLoopbackHost(url.hostname) && url.port === '4001') {
      return 'http://localhost:4001';
    }
    return trimTrailingSlash(url.toString());
  } catch {
    return fallbackValue;
  }
}

function shouldUseSameOriginRelayProxy(locationUrl, relayOrigin) {
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
