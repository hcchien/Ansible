import { createForumLoginController } from './forum_login_app.mjs';
import {
  WEB_SESSION_TOKEN_KEY,
  clearWebSessionToken,
  readWebSessionToken,
} from './web_session_client.mjs';

const relayInput = document.querySelector('#relay-base-url');
const webOriginInput = document.querySelector('#web-origin');
const startButton = document.querySelector('#start-login');
const pollButton = document.querySelector('#poll-now');
const signOutButton = document.querySelector('#sign-out');
const smokeButton = document.querySelector('#smoke-thread');
const statusLabel = document.querySelector('#status-label');
const challengePanel = document.querySelector('#challenge-panel');
const challengeId = document.querySelector('#challenge-id');
const challengeExpiry = document.querySelector('#challenge-expiry');
const deepLink = document.querySelector('#deep-link');
const qrPayload = document.querySelector('#qr-payload');
const tokenPreview = document.querySelector('#token-preview');
const smokeResult = document.querySelector('#smoke-result');
const errorBox = document.querySelector('#error-box');

let controller = createController();
let pollTimer = null;

relayInput.value = localStorage.getItem('trisaura.relay_base_url') ?? 'http://localhost:4001';
webOriginInput.value = window.location.origin;
renderSignedOut();

startButton.addEventListener('click', async () => {
  stopPolling();
  persistRelay();
  controller = createController();
  setBusy(true);
  showError('');
  smokeResult.textContent = '';

  try {
    const state = await controller.startLogin();
    renderPending(state);
    pollTimer = window.setInterval(pollChallenge, 1800);
  } catch (error) {
    renderSignedOut();
    showError(error.message);
  } finally {
    setBusy(false);
  }
});

pollButton.addEventListener('click', pollChallenge);

signOutButton.addEventListener('click', () => {
  stopPolling();
  clearWebSessionToken(localStorage);
  renderSignedOut();
});

smokeButton.addEventListener('click', async () => {
  showError('');
  smokeResult.textContent = 'Sending smoke request...';

  try {
    const response = await controller.createThreadSmoke({
      title: 'Login challenge smoke test',
    });
    smokeResult.textContent = JSON.stringify(response, null, 2);
  } catch (error) {
    smokeResult.textContent = '';
    showError(error.message);
  }
});

async function pollChallenge() {
  setBusy(true);
  showError('');

  try {
    const state = await controller.pollOnce();

    if (state.status === 'approved') {
      stopPolling();
      renderApproved(state);
    } else if (state.status === 'pending') {
      renderPending(state);
    } else {
      stopPolling();
      renderRetryable(state);
    }
  } catch (error) {
    stopPolling();
    showError(error.message);
  } finally {
    setBusy(false);
  }
}

function createController() {
  return createForumLoginController({
    relayBaseUrl: relayInput.value,
    webOrigin: webOriginInput.value,
    storage: localStorage,
  });
}

function persistRelay() {
  localStorage.setItem('trisaura.relay_base_url', relayInput.value);
}

function renderSignedOut() {
  const token = readWebSessionToken(localStorage);
  challengePanel.hidden = true;
  pollButton.disabled = true;
  smokeButton.disabled = !token;
  signOutButton.disabled = !token;
  statusLabel.textContent = token ? 'Token present' : 'Signed out';
  tokenPreview.textContent = token ? maskToken(token) : 'No browser session token';
}

function renderPending(state) {
  challengePanel.hidden = false;
  pollButton.disabled = false;
  smokeButton.disabled = true;
  signOutButton.disabled = false;
  statusLabel.textContent = 'Waiting for app approval';
  challengeId.textContent = state.challenge.challengeId;
  challengeExpiry.textContent = state.challenge.expiresAt;
  deepLink.href = state.challenge.deepLink;
  deepLink.textContent = state.challenge.deepLink;
  qrPayload.value = state.challenge.qrPayload;
  tokenPreview.textContent = 'No token stored yet';
}

function renderApproved(state) {
  challengePanel.hidden = false;
  pollButton.disabled = true;
  smokeButton.disabled = false;
  signOutButton.disabled = false;
  statusLabel.textContent = `Approved as ${state.trustTier ?? 'self_custody_did'}`;
  tokenPreview.textContent = maskToken(readWebSessionToken(localStorage));
}

function renderRetryable(state) {
  pollButton.disabled = true;
  smokeButton.disabled = true;
  signOutButton.disabled = false;
  statusLabel.textContent = `${state.status}. Start a new challenge.`;
  tokenPreview.textContent = 'No browser session token';
}

function setBusy(isBusy) {
  startButton.disabled = isBusy;
  pollButton.disabled = isBusy || !controller.getState().challenge;
}

function showError(message) {
  errorBox.hidden = !message;
  errorBox.textContent = message;
}

function stopPolling() {
  if (pollTimer) {
    window.clearInterval(pollTimer);
    pollTimer = null;
  }
}

function maskToken(token) {
  if (!token) {
    return 'No browser session token';
  }

  return `${token.slice(0, 8)}... stored in ${WEB_SESSION_TOKEN_KEY}`;
}
