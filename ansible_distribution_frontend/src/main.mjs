import { createForumDataAdapter } from './forum_data_adapter.mjs';
import { createForumUiApp } from './forum_ui_app.mjs';
import { createPageController } from './page_routes.mjs';
import { createSessionLifecycle } from './session_lifecycle.mjs';
import { resolveFrontendRuntimeConfig } from './runtime_config.mjs';
import { setCurrentLocale } from './web_i18n.mjs';

const root = document.querySelector('#forum-root');

if (!root) {
  throw new Error('Missing #forum-root mount element');
}

const { relayBaseUrl, relayOrigin, webOrigin, locale } = resolveFrontendRuntimeConfig({
  location: window.location,
  storage: localStorage,
  navigatorLike: navigator,
});
setCurrentLocale(locale);
document.documentElement.lang = locale;

const sessionLifecycle = createSessionLifecycle({
  relayBaseUrl,
  relayOrigin,
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
  forumDataAdapter,
  storage: localStorage,
  windowLike: window,
}).start();
