import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { createServer as createHttpServer, request as httpRequest } from 'node:http';
import { request as httpsRequest } from 'node:https';
import { dirname, extname, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const DEFAULT_PORT = 5173;
const DEFAULT_HOST = '127.0.0.1';
const DEFAULT_RELAY_BASE_URL = 'http://localhost:4001';
const SERVER_ROOT = dirname(fileURLToPath(import.meta.url));

const MIME_TYPES = Object.freeze({
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
});

// Security headers applied to every response served by this frontend server.
const SECURITY_HEADERS = Object.freeze({
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'strict-origin-when-cross-origin',
  // CSP: same-origin scripts only; no inline scripts; no plugins; no framing.
  // The frontend is a plain ES-module SPA with no inline event handlers or
  // eval usage, so this policy is safe to enforce without nonces.
  'content-security-policy': [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self' data:",
    "connect-src 'self'",
    "font-src 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join('; '),
});

const HOP_BY_HOP_HEADERS = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

export function createFrontendServer({
  rootDir = SERVER_ROOT,
  relayBaseUrl = process.env.RELAY_BASE_URL ?? DEFAULT_RELAY_BASE_URL,
  logger = console,
} = {}) {
  const resolvedRoot = resolve(rootDir);
  const resolvedRelayBaseUrl = normalizeRelayProxyBaseUrl(relayBaseUrl);

  return createHttpServer((request, response) => {
    handleRequest(request, response, {
      rootDir: resolvedRoot,
      relayBaseUrl: resolvedRelayBaseUrl,
      logger,
    }).catch((error) => {
      logger?.error?.(error);
      sendJson(response, 500, { error: 'frontend_server_error' });
    });
  });
}

export function startFrontendServer({
  host = process.env.HOST ?? DEFAULT_HOST,
  port = Number(process.env.PORT ?? DEFAULT_PORT),
  relayBaseUrl = process.env.RELAY_BASE_URL ?? DEFAULT_RELAY_BASE_URL,
  rootDir = SERVER_ROOT,
  logger = console,
} = {}) {
  const server = createFrontendServer({ rootDir, relayBaseUrl, logger });

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      server.off('error', reject);
      logger?.log?.(
        `Elix web frontend listening on http://${host}:${server.address().port} -> ${trimTrailingSlash(relayBaseUrl)}`,
      );
      resolve(server);
    });
  });
}

async function handleRequest(request, response, context) {
  const url = new URL(request.url ?? '/', 'http://frontend.local');

  if (url.pathname === '/healthz') {
    // Do not include relayBaseUrl in the response — it reveals internal service
    // topology (host, port) to any caller that can reach this endpoint.
    sendJson(response, 200, {
      ok: true,
      service: 'elix-web-frontend',
    });
    return;
  }

  if (url.pathname.startsWith('/api/')) {
    await proxyRelayRequest(request, response, url, context);
    return;
  }

  await serveFrontendAsset(request, response, url, context);
}

async function serveFrontendAsset(request, response, url, { rootDir }) {
  if (!['GET', 'HEAD'].includes(request.method ?? 'GET')) {
    response.writeHead(405, { ...SECURITY_HEADERS, allow: 'GET, HEAD' });
    response.end();
    return;
  }

  const pathname = safeDecodePath(url.pathname);
  const requestedPath = pathname === '/' ? '/index.html' : pathname;
  const filePath = resolve(rootDir, `.${requestedPath}`);

  if (!isPathInside(filePath, rootDir)) {
    response.writeHead(403, { ...SECURITY_HEADERS, 'content-type': 'text/plain; charset=utf-8' });
    response.end('Forbidden');
    return;
  }

  const resolvedFilePath = await resolveStaticFile(filePath, rootDir, pathname);
  if (!resolvedFilePath) {
    response.writeHead(404, { ...SECURITY_HEADERS, 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }

  await streamFile(response, resolvedFilePath, request.method === 'HEAD');
}

async function resolveStaticFile(filePath, rootDir, pathname) {
  try {
    const fileStat = await stat(filePath);
    if (fileStat.isFile()) return filePath;
  } catch {
    // Fall through to SPA fallback.
  }

  if (!extname(pathname)) {
    return resolve(rootDir, 'index.html');
  }

  return null;
}

async function streamFile(response, filePath, headOnly) {
  const fileStat = await stat(filePath);
  response.writeHead(200, {
    ...SECURITY_HEADERS,
    'content-type': MIME_TYPES[extname(filePath)] ?? 'application/octet-stream',
    'content-length': fileStat.size,
    'cache-control': 'no-store',
  });

  if (headOnly) {
    response.end();
    return;
  }

  await new Promise((resolvePromise, reject) => {
    createReadStream(filePath)
      .once('error', reject)
      .once('end', resolvePromise)
      .pipe(response);
  });
}

function proxyRelayRequest(clientRequest, clientResponse, url, { relayBaseUrl }) {
  return new Promise((resolvePromise) => {
    const relayUrl = new URL(`${url.pathname}${url.search}`, relayBaseUrl);
    const requestFn = relayUrl.protocol === 'https:' ? httpsRequest : httpRequest;
    const headers = filterProxyHeaders(clientRequest.headers);
    headers.host = relayUrl.host;

    const relayRequest = requestFn(
      relayUrl,
      {
        method: clientRequest.method,
        headers,
      },
      (relayResponse) => {
        // Merge security headers last so they cannot be overridden by relay.
        const proxiedHeaders = {
          ...filterProxyHeaders(relayResponse.headers),
          ...SECURITY_HEADERS,
        };
        clientResponse.writeHead(relayResponse.statusCode ?? 502, proxiedHeaders);
        relayResponse.pipe(clientResponse);
        relayResponse.on('end', resolvePromise);
      },
    );

    relayRequest.on('error', () => {
      sendJson(clientResponse, 502, { error: 'relay_unavailable' });
      resolvePromise();
    });

    clientRequest.pipe(relayRequest);
  });
}

function filterProxyHeaders(headers) {
  return Object.fromEntries(
    Object.entries(headers).filter(([name]) => !HOP_BY_HOP_HEADERS.has(name.toLowerCase())),
  );
}

function sendJson(response, status, body) {
  const json = JSON.stringify(body);
  response.writeHead(status, {
    ...SECURITY_HEADERS,
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(json),
    'cache-control': 'no-store',
  });
  response.end(json);
}

function safeDecodePath(pathname) {
  try {
    return decodeURIComponent(pathname);
  } catch {
    return '/';
  }
}

function isPathInside(filePath, rootDir) {
  const normalizedRoot = rootDir.endsWith(sep) ? rootDir : `${rootDir}${sep}`;
  return filePath === rootDir || filePath.startsWith(normalizedRoot);
}

function trimTrailingSlash(value) {
  return String(value).replace(/\/+$/, '');
}

function normalizeRelayProxyBaseUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === 'http:' && url.hostname === 'localhost' && url.port === '4001') {
      url.hostname = '127.0.0.1';
    }
    return trimTrailingSlash(url.toString());
  } catch {
    return trimTrailingSlash(value);
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  startFrontendServer();
}
