import { normalizeFrontendError } from './error_taxonomy.mjs';
import { renderPageBody } from './forum_page_renderers.mjs';
import { renderAppShell } from './forum_shell_renderer.mjs';
import { buildAppViewModel } from './state_model.mjs';
import { WEB_SESSION_TOKEN_KEY } from './web_session_client.mjs';

export function createForumUiApp({
  root,
  pageController,
  sessionLifecycle,
  storage,
  windowLike = globalThis.window,
}) {
  let state = null;
  let loginState = null;
  let uiError = null;
  let pollTimer = null;
  let bound = false;
  let pendingHashLoad = null;

  const handleClick = async (event) => {
    const actionElement = findActionElement(event.target, root);
    const action = actionElement?.dataset?.action;
    if (!action) return;

    if (typeof event.preventDefault === 'function') {
      event.preventDefault();
    }

    try {
      if (action === 'start-login') {
        await startLogin();
      } else if (action === 'poll-login') {
        await pollLoginOnce();
      } else if (action === 'revoke-session') {
        await revokeSession();
      } else if (action === 'sign-out') {
        await signOut();
      }
    } catch (error) {
      renderUiError(error);
    }
  };

  const handleHashChange = async () => {
    const loadPromise = loadCurrentRoute();

    if (pendingHashLoad) {
      const pending = pendingHashLoad;
      pendingHashLoad = null;
      loadPromise.then(pending.resolve, pending.reject);
    }

    return loadPromise;
  };

  async function start() {
    bindEvents();
    return loadCurrentRoute();
  }

  async function navigate(hash) {
    const previousHash = windowLike.location.hash;
    const relyOnHashchange = previousHash !== hash && shouldRelyOnHashchange(windowLike);
    let hashLoadPromise = null;

    if (relyOnHashchange) {
      pendingHashLoad = {};
      hashLoadPromise = new Promise((resolve, reject) => {
        pendingHashLoad.resolve = resolve;
        pendingHashLoad.reject = reject;
      });
      pendingHashLoad.promise = hashLoadPromise;
    }

    windowLike.location.hash = hash;

    if (relyOnHashchange) {
      return hashLoadPromise;
    }

    return loadCurrentRoute();
  }

  async function loadCurrentRoute() {
    try {
      state = await pageController.loadCurrentRoute();
      uiError = null;
      render();
      return state;
    } catch (error) {
      renderUiError(error);
      throw error;
    }
  }

  async function startLogin() {
    try {
      loginState = await sessionLifecycle.startAppLogin();
      uiError = null;
      render();
      return loginState;
    } catch (error) {
      renderUiError(error);
      throw error;
    }
  }

  async function pollLoginOnce() {
    try {
      loginState = await sessionLifecycle.pollLoginChallenge();
      uiError = null;
      render();
      return loginState;
    } catch (error) {
      renderUiError(error);
      throw error;
    }
  }

  async function revokeSession() {
    try {
      await sessionLifecycle.revokeCurrentSession();
      loginState = null;
      uiError = null;
      return loadCurrentRoute();
    } catch (error) {
      renderUiError(error);
      throw error;
    }
  }

  async function signOut() {
    try {
      storage.removeItem(WEB_SESSION_TOKEN_KEY);
      loginState = null;
      uiError = null;
      return loadCurrentRoute();
    } catch (error) {
      renderUiError(error);
      throw error;
    }
  }

  function render() {
    if (!root || !state?.viewModel) return;

    const viewModel = viewModelForRender();
    const login = loginStateForRender();
    const bodyHtml = renderPageBody(viewModel, { login });
    root.innerHTML = renderAppShell({ viewModel, bodyHtml });
  }

  function stop() {
    if (pollTimer) {
      windowLike.clearInterval(pollTimer);
      pollTimer = null;
    }

    if (bound) {
      root?.removeEventListener?.('click', handleClick);
      windowLike?.removeEventListener?.('hashchange', handleHashChange);
      bound = false;
    }
  }

  function bindEvents() {
    if (bound) return;

    root?.addEventListener?.('click', handleClick);
    windowLike?.addEventListener?.('hashchange', handleHashChange);
    bound = true;
  }

  function viewModelForRender() {
    const loginViewModel = loginState?.viewModel;
    let viewModel = state.viewModel;

    if (!loginViewModel?.authenticated) {
      return uiError ? { ...viewModel, error: uiError } : viewModel;
    }

    viewModel = buildAppViewModel({
      route: state.route,
      session: loginViewModel,
      forum: state.forum,
      loading: state.loading,
      error: state.error,
    });

    return uiError ? { ...viewModel, error: uiError } : viewModel;
  }

  function loginStateForRender() {
    if (!loginState) return null;

    return {
      status: loginState.status === 'login_pending' ? 'pending' : loginState.status,
      challenge: loginState.viewModel?.challenge ?? loginState.challenge,
      requestedScopes: loginState.viewModel?.scopes ?? [],
    };
  }

  function renderUiError(error) {
    uiError = normalizeFrontendError(error);
    state = state ?? pageController.getState?.() ?? null;
    render();
  }

  return {
    start,
    navigate,
    loadCurrentRoute,
    startLogin,
    pollLoginOnce,
    revokeSession,
    signOut,
    render,
    stop,
  };
}

function findActionElement(target, root) {
  if (!target) return null;

  if (typeof target.closest === 'function') {
    const element = target.closest('[data-action]');
    return isWithinRoot(element, root) ? element : null;
  }

  let node = target;
  while (node) {
    if (node.dataset?.action) {
      return isWithinRoot(node, root) ? node : null;
    }
    node = node.parentElement;
  }

  return null;
}

function isWithinRoot(element, root) {
  if (!element || !root) return false;
  if (element === root) return true;
  if (typeof root.contains === 'function') {
    return root.contains(element);
  }

  let node = element;
  while (node) {
    if (node === root) return true;
    node = node.parentElement;
  }

  return false;
}

function shouldRelyOnHashchange(windowLike) {
  return (
    typeof windowLike?.addEventListener === 'function' &&
    windowLike.dispatchesHashchange !== false
  );
}
