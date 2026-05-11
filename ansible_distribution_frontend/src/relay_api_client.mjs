const DEFAULT_SESSION_TOKEN_KEY = 'trisaura.web_session_token';

export class RelayApiError extends Error {
  constructor(message, { status, code, detail, body } = {}) {
    super(message);
    this.name = 'RelayApiError';
    this.status = status;
    this.code = code;
    this.detail = detail;
    this.body = body;
  }
}

export function createRelayApiClient({
  relayBaseUrl,
  fetchImpl = globalThis.fetch,
  storage = globalThis.localStorage,
  sessionTokenKey = DEFAULT_SESSION_TOKEN_KEY,
}) {
  assertFetch(fetchImpl);

  async function getJson(path, options = {}) {
    return requestJson('GET', path, undefined, options);
  }

  async function postJson(path, body = {}, options = {}) {
    return requestJson('POST', path, body, options);
  }

  async function requestJson(method, path, body, options) {
    const headers = { accept: 'application/json' };

    if (body !== undefined) {
      headers['content-type'] = 'application/json';
    }

    if (options.authenticated) {
      const token = options.sessionToken ?? storage?.getItem(sessionTokenKey);

      if (!token) {
        throw new Error('web session token is required');
      }

      headers.authorization = `Bearer ${token}`;
    }

    const response = await fetchImpl(`${trimTrailingSlash(relayBaseUrl)}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const responseBody = await parseResponseBody(response);

    if (!response.ok) {
      if (response.status === 401 && options.authenticated) {
        storage?.removeItem(sessionTokenKey);
      }

      throw new RelayApiError(
        responseBody?.error ?? `request failed with HTTP ${response.status}`,
        {
          status: response.status,
          code: responseBody?.error,
          detail: responseBody?.detail,
          body: responseBody,
        },
      );
    }

    return responseBody;
  }

  return { getJson, postJson };
}

export function trimTrailingSlash(value) {
  return value.replace(/\/+$/, '');
}

function assertFetch(fetchImpl) {
  if (typeof fetchImpl !== 'function') {
    throw new TypeError('fetchImpl is required');
  }
}

async function parseResponseBody(response) {
  try {
    return await response.json();
  } catch (_error) {
    return null;
  }
}
