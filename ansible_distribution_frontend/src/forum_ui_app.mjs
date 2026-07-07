import { normalizeFrontendError } from './error_taxonomy.mjs';
import { renderPageBody } from './forum_page_renderers.mjs';
import { renderAppShell } from './forum_shell_renderer.mjs';
import { moderationActionLabel, reasonCodeLabel } from './forum_ui_text.mjs';
import { buildAppViewModel } from './state_model.mjs';
import { t } from './web_i18n.mjs';
import { WEB_SESSION_TOKEN_KEY } from './web_session_client.mjs';

const UI_STORAGE_KEYS = Object.freeze({
  activeScene: 'elix.focus.active_scene',
  personalTheme: 'elix.focus.personal_theme',
  forumTheme: 'elix.focus.forum_theme',
  motionMode: 'elix.focus.motion_mode',
  coachmarkDismissed: 'elix.focus.coachmark_dismissed',
});

const DEFAULT_UI_PREFERENCES = Object.freeze({
  activeScene: 'personal',
  personalTheme: 'auto',
  forumTheme: 'auto',
  motionMode: 'book',
  coachmarkDismissed: false,
});

export function createForumUiApp({
  root,
  pageController,
  sessionLifecycle,
  forumDataAdapter = null,
  storage,
  windowLike = globalThis.window,
}) {
  let state = null;
  let loginState = null;
  let uiError = null;
  let uiNotice = null;
  let threadDraft = null;
  let uiPreferences = readUiPreferences(storage);
  let pollTimer = null;
  let bound = false;
  let pendingHashLoad = null;
  let swipeStartX = null;

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
      } else if (action === 'select-scene') {
        selectScene(actionElement.dataset.scene);
      } else if (action === 'set-scene-theme') {
        setSceneTheme(actionElement.dataset.scene, actionElement.dataset.theme);
      } else if (action === 'set-motion-mode') {
        setMotionMode(actionElement.dataset.motion);
      } else if (action === 'dismiss-swipe-coachmark') {
        dismissSwipeCoachmark();
      } else if (action === 'new-thread') {
        openThreadDraft(actionElement);
      } else if (action === 'cancel-thread-draft') {
        cancelThreadDraft();
      } else if (action === 'submit-thread-draft') {
        await submitThreadDraft(actionElement);
      } else if (action === 'submit-report') {
        await submitReport(actionElement);
      } else if (action === 'moderation-action') {
        await submitModerationAction(actionElement);
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

  const handlePointerDown = (event) => {
    if (!findFocusStageElement(event.target, root)) return;
    swipeStartX = Number(event.clientX);
  };

  const handlePointerUp = (event) => {
    if (swipeStartX === null || !findFocusStageElement(event.target, root)) {
      swipeStartX = null;
      return;
    }

    const deltaX = Number(event.clientX) - swipeStartX;
    swipeStartX = null;

    if (deltaX <= -48) {
      selectScene('forum');
    } else if (deltaX >= 48) {
      selectScene('personal');
    }
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

  function openThreadDraft(actionElement) {
    threadDraft = {
      boardId: currentBoardId(actionElement),
      title: '',
    };
    uiError = null;
    render();
  }

  function cancelThreadDraft() {
    threadDraft = null;
    render();
  }

  async function submitThreadDraft(actionElement) {
    if (!forumDataAdapter?.submitThreadDraft) return;

    try {
      const title = readThreadDraftTitle(actionElement);
      const trimmedTitle = String(title).trim();
      if (!trimmedTitle) return;

      await forumDataAdapter.submitThreadDraft({
        title: trimmedTitle,
        boardId: currentBoardId(actionElement),
        sessionViewModel: currentSessionViewModel(),
      });

      uiError = null;
      threadDraft = null;
      uiNotice = {
        tone: 'success',
        title: t('compose.threadSubmitted.title'),
        message: t('compose.threadSubmitted.message'),
      };
      state = await pageController.loadCurrentRoute();
      render();
    } catch (error) {
      renderUiError(error);
    }
  }

  function readThreadDraftTitle(actionElement) {
    const form = findThreadDraftForm(actionElement, root);
    return (
      form?.querySelector?.('[data-thread-draft-title]')?.value ??
      actionElement?.dataset?.title ??
      ''
    );
  }

  // Submits a report from an inline report form. The target travels on the
  // action element's dataset; reason/note come from the form fields (with a
  // dataset fallback so non-DOM hosts can drive the same action).
  async function submitReport(actionElement) {
    if (!forumDataAdapter?.submitReport) return;

    try {
      const form = findReportForm(actionElement, root);
      const dataset = { ...(form?.dataset ?? {}), ...(actionElement.dataset ?? {}) };
      const reasonCode =
        form?.querySelector?.('[data-report-reason]')?.value ?? dataset.reasonCode;
      const note =
        form?.querySelector?.('[data-report-note]')?.value ?? dataset.note ?? '';

      const { duplicate } = await forumDataAdapter.submitReport({
        targetKind: dataset.targetKind,
        targetRef: dataset.targetRef,
        boardId: dataset.boardId,
        reasonCode,
        note,
        sessionViewModel: currentSessionViewModel(),
      });

      uiError = null;
      uiNotice = duplicate
        ? {
            tone: 'warning',
            title: t('report.duplicate.title'),
            message: t('report.duplicate.message'),
          }
        : {
            tone: 'success',
            title: t('report.submitted.title'),
            message: t('report.submitted.message'),
          };
      render();
    } catch (error) {
      renderUiError(error);
    }
  }

  // Runs a moderation action from the console queue, then reloads the route
  // so the open-report queue and audit history reflect the relay state.
  async function submitModerationAction(actionElement) {
    if (!forumDataAdapter?.submitModerationAction) return;

    try {
      const dataset = actionElement.dataset ?? {};
      const recorded = await forumDataAdapter.submitModerationAction({
        action: dataset.modAction,
        targetRef: dataset.targetRef,
        boardId: dataset.boardId,
        reasonCode: dataset.reasonCode,
        reportId: dataset.reportId || null,
      });

      uiError = null;
      uiNotice = {
        tone: 'success',
        title: t('moderation.actionDone.title'),
        message: t('moderation.actionDone.message', {
          action: moderationActionLabel(recorded?.action ?? dataset.modAction),
          board: recorded?.boardId ?? dataset.boardId ?? '',
          reason: reasonCodeLabel(recorded?.reasonCode ?? dataset.reasonCode),
        }),
      };
      state = await pageController.loadCurrentRoute();
      render();
    } catch (error) {
      renderUiError(error);
    }
  }

  function currentSessionViewModel() {
    if (loginState?.viewModel?.authenticated) {
      return loginState.viewModel;
    }

    return state?.session ?? null;
  }

  function currentBoardId(actionElement) {
    const datasetBoardId = actionElement?.dataset?.boardId;
    if (datasetBoardId) return datasetBoardId;

    return (
      state?.viewModel?.board?.id ||
      state?.viewModel?.board?.slug ||
      state?.viewModel?.boards?.[0]?.id ||
      state?.viewModel?.boards?.[0]?.slug ||
      null
    );
  }

  function render() {
    if (!root || !state?.viewModel) return;

    const viewModel = viewModelForRender();
    const login = loginStateForRender();
    const bodyHtml = renderPageBody(viewModel, {
      login,
      preferences: uiPreferences,
      notice: uiNotice,
      threadDraft,
    });
    root.innerHTML = renderAppShell({ viewModel, bodyHtml, uiPreferences });
    uiNotice = null;
  }

  function stop() {
    if (pollTimer) {
      windowLike.clearInterval(pollTimer);
      pollTimer = null;
    }

    if (bound) {
      root?.removeEventListener?.('click', handleClick);
      root?.removeEventListener?.('pointerdown', handlePointerDown);
      root?.removeEventListener?.('pointerup', handlePointerUp);
      windowLike?.removeEventListener?.('hashchange', handleHashChange);
      bound = false;
    }
  }

  function bindEvents() {
    if (bound) return;

    root?.addEventListener?.('click', handleClick);
    root?.addEventListener?.('pointerdown', handlePointerDown);
    root?.addEventListener?.('pointerup', handlePointerUp);
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
    uiNotice = null;
    state = state ?? pageController.getState?.() ?? null;
    render();
  }

  function selectScene(scene) {
    const nextScene = normalizeScene(scene);
    uiPreferences = { ...uiPreferences, activeScene: nextScene, coachmarkDismissed: true };
    writeUiPreference(storage, UI_STORAGE_KEYS.activeScene, nextScene);
    writeUiPreference(storage, UI_STORAGE_KEYS.coachmarkDismissed, 'true');
    render();
  }

  function setSceneTheme(scene, theme) {
    const sceneKey = normalizeScene(scene);
    const themeValue = normalizeTheme(theme);
    const preferenceKey = sceneKey === 'forum' ? 'forumTheme' : 'personalTheme';
    const storageKey =
      sceneKey === 'forum' ? UI_STORAGE_KEYS.forumTheme : UI_STORAGE_KEYS.personalTheme;

    uiPreferences = { ...uiPreferences, [preferenceKey]: themeValue };
    writeUiPreference(storage, storageKey, themeValue);
    render();
  }

  function setMotionMode(motion) {
    const nextMotion = normalizeMotionMode(motion);
    uiPreferences = { ...uiPreferences, motionMode: nextMotion };
    writeUiPreference(storage, UI_STORAGE_KEYS.motionMode, nextMotion);
    render();
  }

  function dismissSwipeCoachmark() {
    uiPreferences = { ...uiPreferences, coachmarkDismissed: true };
    writeUiPreference(storage, UI_STORAGE_KEYS.coachmarkDismissed, 'true');
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

function readUiPreferences(storage) {
  return {
    activeScene: normalizeScene(storage?.getItem?.(UI_STORAGE_KEYS.activeScene)),
    personalTheme: normalizeTheme(storage?.getItem?.(UI_STORAGE_KEYS.personalTheme)),
    forumTheme: normalizeTheme(storage?.getItem?.(UI_STORAGE_KEYS.forumTheme)),
    motionMode: normalizeMotionMode(storage?.getItem?.(UI_STORAGE_KEYS.motionMode)),
    coachmarkDismissed: storage?.getItem?.(UI_STORAGE_KEYS.coachmarkDismissed) === 'true',
  };
}

function writeUiPreference(storage, key, value) {
  storage?.setItem?.(key, value);
}

function normalizeScene(value) {
  return value === 'forum' ? 'forum' : DEFAULT_UI_PREFERENCES.activeScene;
}

function normalizeTheme(value) {
  return ['light', 'dark', 'auto'].includes(value) ? value : DEFAULT_UI_PREFERENCES.personalTheme;
}

function normalizeMotionMode(value) {
  return ['slide', 'book', 'cube'].includes(value) ? value : DEFAULT_UI_PREFERENCES.motionMode;
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

function findReportForm(element, root) {
  if (!element) return null;

  if (typeof element.closest === 'function') {
    const form = element.closest('[data-report-form]');
    return isWithinRoot(form, root) ? form : null;
  }

  let node = element;
  while (node) {
    if (node.dataset && 'reportForm' in node.dataset) {
      return isWithinRoot(node, root) ? node : null;
    }
    node = node.parentElement;
  }

  return null;
}

function findThreadDraftForm(element, root) {
  if (!element) return null;

  if (typeof element.closest === 'function') {
    const form = element.closest('[data-thread-draft-form]');
    return isWithinRoot(form, root) ? form : null;
  }

  let node = element;
  while (node) {
    if (node.dataset && 'threadDraftForm' in node.dataset) {
      return isWithinRoot(node, root) ? node : null;
    }
    node = node.parentElement;
  }

  return null;
}

function findFocusStageElement(target, root) {
  if (!target) return null;

  if (typeof target.closest === 'function') {
    const element = target.closest('.mobile-focus-stage');
    return isWithinRoot(element, root) ? element : null;
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
