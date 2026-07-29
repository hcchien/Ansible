import { escapeHtml } from './forum_shell_renderer.mjs';
import { getCurrentLocale } from './web_i18n.mjs';

const COPY = Object.freeze({
  'zh-Hant': {
    kicker: '從這裡開始', title: 'Elix 是什麼？',
    intro: 'Elix 是一個讓人可以好好說話的社群 App。你不必先理解 DID、Relay 或憑證；先把它當成一個可以閱讀、加入討論，也能自己決定資料怎麼流動的地方。',
    startTitle: '先記得這三件事就好',
    steps: [['先逛逛', '不登入也能閱讀公開看板與討論。'], ['想說話再登入', '登入後才能以自己的身分簽署發文；不需要一開始就完成所有設定。'], ['需要時再升級', '有些看板為了減少假帳號，才會要求更高的驗證層級。']],
    questions: [
      ['為什麼 Elix 要有「身分」？', '因為公開討論很容易被大量假帳號與自動化淹沒。Elix 讓你可以用自己的身分簽署內容，讓社群知道這則內容不是隨手可大量複製的匿名帳號產生的。這不等於必須公開真名。'],
      ['我一定要做真人驗證嗎？', '不用。閱讀公開內容與一般使用不以真人驗證為前提。只有個別看板選擇提高發文門檻時，才可能要求「已驗證真人」；看板應在你發文前清楚說明規則。'],
      ['驗證後，Elix 會拿到我的身分證或護照資料嗎？', '預設不會把姓名、身分證或護照號碼放進公開貼文、憑證或 Relay 資料。驗證的目的，是只確認需要的事實，例如「這是一位已驗證的真人」；不需要提供原始身分資料給討論區。'],
      ['我的貼文是私密的嗎？', '不是自動私密。公開或聯邦發布的內容會被視為可傳播；私密內容則必須在離開你的受信任範圍前受到保護。發送前請依畫面上的可見範圍選擇。'],
      ['誰決定我可以說什麼？', '每個看板可以訂自己的規則與發文門檻。Elix 的系統規則只處理安全、垃圾訊息、操弄、隱私與法律等高風險問題。你可以選擇、離開或封鎖看板與主機。'],
      ['Relay、Forum Host、AppView 是什麼？', '可以先不用管。簡單說：Relay 幫你連線與同步，Forum Host 管理一個討論區的規則與內容，AppView 幫你閱讀公開內容。它們不該取代你對自己身分與資料的控制。'],
      ['我現在該做什麼？', '從一個你感興趣的公開看板開始。先讀，再決定要不要登入與參與；遇到需要驗證的看板，畫面會告訴你原因和下一步。'],
    ], cta: '瀏覽公開看板',
  },
  en: {
    kicker: 'Start here', title: 'What is Elix?', intro: 'Elix is a social app for thoughtful conversation. You do not need to understand DIDs, relays, or credentials first: begin by reading, then choose how you participate and where your data goes.', startTitle: 'Just remember these three things',
    steps: [['Browse first', 'Public boards and discussions are readable without signing in.'], ['Sign in when you want to speak', 'Signing in lets you sign your own posts; you do not need to complete every setup step first.'], ['Upgrade only when needed', 'Some boards use higher assurance to reduce fake accounts.']],
    questions: [['Why does Elix use identity?', 'It helps communities resist cheap fake accounts and automation. Signing a post shows it came from your identity, without requiring you to publish your real name.'], ['Do I have to verify that I am human?', 'No. Public reading and ordinary use do not require it. A board may ask for verified-human status before posting, and should explain that rule before you post.'], ['Does verification give Elix my ID or passport details?', 'By default, raw identity details are not put in public posts, credentials, or relay data. Verification should reveal only the fact needed, such as verified-human status.'], ['Are my posts private?', 'Not automatically. Public or federated content can spread; private content must be protected before it leaves your trusted boundary. Check the visibility setting before sending.'], ['Who decides what I can say?', 'Each board can set its own rules and posting requirements. System-wide rules are limited to high-risk concerns such as safety, spam, manipulation, privacy, and legal obligations.'], ['What are a Relay, Forum Host, and AppView?', 'You can safely ignore them for now. In brief: a Relay connects and syncs, a Forum Host runs a discussion space, and an AppView helps read public content. They should not replace your control over your identity or data.'], ['What should I do now?', 'Start with a public board that interests you. Read first, then decide whether to sign in and join the conversation.']], cta: 'Browse public boards',
  },
});

export function renderElixFaq() {
  const copy = COPY[getCurrentLocale()] ?? COPY['zh-Hant'];
  return `<section class="faq-page" aria-labelledby="faq-title">
    <header class="faq-hero"><p class="section-label">${escapeHtml(copy.kicker)}</p><h1 id="faq-title">${escapeHtml(copy.title)}</h1><p>${escapeHtml(copy.intro)}</p><a class="primary-action" href="#/boards">${escapeHtml(copy.cta)}</a></header>
    <section class="faq-start" aria-labelledby="faq-start-title"><h2 id="faq-start-title">${escapeHtml(copy.startTitle)}</h2><ol>${copy.steps.map(([title, text]) => `<li><strong>${escapeHtml(title)}</strong><span>${escapeHtml(text)}</span></li>`).join('')}</ol></section>
    <section class="faq-list" aria-label="Frequently asked questions">${copy.questions.map(([question, answer]) => `<details><summary>${escapeHtml(question)}</summary><p>${escapeHtml(answer)}</p></details>`).join('')}</section>
  </section>`;
}
