import { createForumDataAdapter } from './forum_data_adapter.mjs';
import { createForumUiApp } from './forum_ui_app.mjs';
import { createPageController } from './page_routes.mjs';
import { createSessionLifecycle } from './session_lifecycle.mjs';

const root = document.querySelector('#forum-root');

if (!root) {
  throw new Error('Missing #forum-root mount element');
}

const relayBaseUrl = localStorage.getItem('trisaura.relay_base_url') ?? 'http://localhost:4001';
const webOrigin = window.location.origin;

const sessionLifecycle = createSessionLifecycle({
  relayBaseUrl,
  webOrigin,
  storage: localStorage,
});
const forumDataAdapter = createForumDataAdapter({
  relayBaseUrl,
  storage: localStorage,
});
const pageController = createPageController({
  sessionLifecycle,
  forumDataAdapter,
});

createForumUiApp({
  root,
  pageController,
  sessionLifecycle,
  storage: localStorage,
  windowLike: window,
}).start();
