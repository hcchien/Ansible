// Server-rendered legal / policy pages.
//
// App Store and Play Store reviewers open the privacy-policy and
// account-deletion URLs directly, without running the SPA, so these pages are
// real path-based documents rendered entirely on the server (server.mjs serves
// them before the SPA fallback). Each page is bilingual on a single document:
// Traditional Chinese first, English below under the `#en` anchor.
//
// Content contract: everything stated here must stay accurate to the actual
// data flows (device / relay / issuer / appview) and to the engineering
// constitution's data promises (docs/superpowers/specs/
// 2026-05-24-tris-aura-engineering-constitution-design.md). Do not add claims
// about collection we do not do — and do not soften the append-only-log
// honesty in the deletion sections.

import { DEFAULT_LOCALE, resolveLocale } from './web_i18n.mjs';

export const LEGAL_EFFECTIVE_DATE = '2026-07-07';
export const LEGAL_EFFECTIVE_DATE_ZH = '2026 年 7 月 7 日';
export const PRIVACY_CONTACT_EMAIL = 'privacy@reviz.tw';
export const SUPPORT_CONTACT_EMAIL = 'support@reviz.tw';

export const LEGAL_PAGE_PATHS = Object.freeze([
  '/privacy',
  '/terms',
  '/about',
  '/support',
  '/account-deletion',
  '/child-safety',
]);

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

const NAV_ITEMS = Object.freeze([
  { path: '/privacy', zh: '隱私權政策', en: 'Privacy' },
  { path: '/terms', zh: '服務條款', en: 'Terms' },
  { path: '/about', zh: '關於', en: 'About' },
  { path: '/support', zh: '支援', en: 'Support' },
  { path: '/account-deletion', zh: '刪除帳號', en: 'Delete account' },
  { path: '/child-safety', zh: '兒少安全', en: 'Child safety' },
]);

function layout({ path, title, body, locale }) {
  const labelKey = locale === 'en' ? 'en' : 'zh';
  const alternateLocale = locale === 'en' ? 'zh-Hant' : 'en';
  const alternateLabel = locale === 'en' ? '中文版本' : 'English version';
  const footerDate =
    locale === 'en'
      ? `Effective date: ${LEGAL_EFFECTIVE_DATE}`
      : `生效日期：${LEGAL_EFFECTIVE_DATE_ZH} (${LEGAL_EFFECTIVE_DATE})`;
  const footerContact = locale === 'en' ? 'Contact' : '聯絡';
  const nav = NAV_ITEMS.map((item) => {
    const current = item.path === path ? ' aria-current="page"' : '';
    return `<a href="${localizedHref(item.path, locale)}"${current}>${item[labelKey]}</a>`;
  }).join('\n        ');

  return `<!doctype html>
<html lang="${locale}">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title} · Elix</title>
    <link rel="stylesheet" href="/src/styles.css" />
    <link rel="stylesheet" href="/src/legal.css" />
  </head>
  <body>
    <main class="legal-page">
      <header class="legal-header">
        <a class="legal-home" href="/?lang=${locale}">Elix</a>
        <nav aria-label="${locale === 'en' ? 'Legal documents' : '法律文件'}">
        ${nav}
        </nav>
      </header>
      <a class="legal-lang-jump" href="${localizedHref(path, alternateLocale)}">${alternateLabel}</a>
${body}
      <footer class="legal-footer">
        <span>${footerDate}</span>
        <span>${footerContact}: <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a></span>
      </footer>
    </main>
  </body>
</html>
`;
}

function localizedHref(path, locale) {
  return `${path}?lang=${locale}`;
}

function localizeLegalBodyLinks(body, locale) {
  return String(body).replace(
    /href="(\/(?:privacy|terms|about|support|account-deletion|child-safety))"/g,
    (_, path) => `href="${localizedHref(path, locale)}"`,
  );
}

export function resolveLegalLocale(value) {
  const raw = String(value ?? '').trim();
  if (!raw) return DEFAULT_LOCALE;

  const candidates = raw
    .split(',')
    .map((entry, index) => {
      const parts = entry.trim().split(';');
      const tag = parts[0]?.trim() ?? '';
      const qParam = parts.find((part) => part.trim().startsWith('q='));
      const q = qParam ? Number(qParam.trim().slice(2)) : 1;
      return {
        tag,
        index,
        q: Number.isFinite(q) ? q : 1,
      };
    })
    .filter((candidate) => candidate.tag)
    .sort((left, right) => right.q - left.q || left.index - right.index);

  for (const { tag } of candidates) {
    const normalized = tag.replaceAll('_', '-').toLowerCase();
    if (normalized === 'en' || normalized.startsWith('en-')) return 'en';
    if (normalized === 'zh' || normalized.startsWith('zh-')) return 'zh-Hant';
  }

  // Legal documents currently have reviewed English and Traditional Chinese
  // editions only. Never label a fallback document as another language.
  return DEFAULT_LOCALE;
}

// ---------------------------------------------------------------------------
// 隱私權政策 / Privacy Policy
// ---------------------------------------------------------------------------

const PRIVACY_ZH = `
      <h1>隱私權政策</h1>
      <p class="legal-effective">生效日期：${LEGAL_EFFECTIVE_DATE_ZH}</p>

      <p>Elix（網域 elix.cool，下稱「本服務」）是一個以自主身分（self-sovereign identity）為基礎的去中心化討論社群。我們的設計原則是：資料盡可能留在你的裝置上；離開裝置的資料，以最小化、經你簽章、可驗證且可攜為前提。本政策說明我們在哪些系統處理哪些資料、保存多久，以及你擁有哪些權利。</p>

      <h2>我們不做的事</h2>
      <ul>
        <li>不使用任何分析（analytics）、追蹤或廣告 SDK，也不嵌入任何第三方追蹤程式碼。</li>
        <li>不建立個人層級的遙測；營運指標僅以匿名「彙總」方式統計，無法對應到任何個人。</li>
        <li>不收集、也不儲存你的地理位置。</li>
        <li>不將 IP 位址寫入任何永久紀錄。</li>
        <li>不販售、出租或分享個人資料給第三方作行銷用途。</li>
      </ul>

      <h2>資料存放在哪裡</h2>

      <h3>你的裝置</h3>
      <ul>
        <li><strong>身分私鑰（Ed25519）</strong>：在你的裝置上產生並保存（軟體保管，標示保管等級 custody_class），並排除於雲端備份之外（Android 使用 noBackupFilesDir、iOS 使用檔案保護機制）。私鑰永遠不會離開你的裝置。</li>
        <li>你的本機資料庫、草稿，以及錢包內的可驗證憑證（Verifiable Credentials，VC）。</li>
      </ul>

      <h3>Relay（訊息中繼服務）</h3>
      <p>Relay 只儲存你選擇公開的內容：</p>
      <ul>
        <li>公開的 DID 與 handle（帳號代稱）。</li>
        <li>你簽章後發布的公開貼文與操作紀錄——這是一份「附加式（append-only）、不可竄改」的簽章紀錄。</li>
        <li>版務（moderation）紀錄。</li>
        <li>裝置推播權杖（僅作為「不含任何內容」的同步提示）。</li>
      </ul>
      <p>Relay <strong>不儲存</strong>你的 email、姓名、電話號碼、身分證字號或位置資訊；IP 位址不留存。</p>

      <h3>Issuer（身分驗證服務）</h3>
      <ul>
        <li>驗證期間的 email 與一次性驗證碼（OTP）僅存在記憶體中約數分鐘，驗證完成即丟棄。</li>
        <li>為防止同一人重複註冊（Sybil 攻擊防護），僅保留一個「含金鑰、不可逆」的雜湊承諾（keyed hashed commitment）；它無法被還原成你的 email 或任何身分資料。</li>
        <li>護照 NFC 晶片資料、台灣行動自然人憑證（MobileMoica）資料，僅在驗證過程中暫時處理，<strong>從不儲存</strong>。</li>
        <li>核發的可驗證憑證（VC）只存放在你裝置上的錢包中；我們保留憑證撤銷（revocation）機制。</li>
      </ul>

      <h3>AppView（閱讀投影服務）</h3>
      <p>AppView 只鏡射 Relay 上「已經公開」的內容，供瀏覽與搜尋使用，不含任何額外的個人資料。</p>

      <h2>資料何時離開你的裝置</h2>
      <p>只有在你主動選擇時，資料才會離開你的裝置：發布公開內容、進行身分驗證，或啟用推播通知。私鑰與未發布的私人資料不會離開裝置。</p>

      <h2>保存期間</h2>
      <div class="legal-table-wrap">
        <table>
          <thead>
            <tr><th>資料</th><th>存放位置</th><th>保存期間</th></tr>
          </thead>
          <tbody>
            <tr><td>身分私鑰（Ed25519）</td><td>僅你的裝置</td><td>直到你清除本機身分或解除安裝</td></tr>
            <tr><td>公開 DID、handle</td><td>Relay</td><td>帳號存續期間（屬公開紀錄）</td></tr>
            <tr><td>已簽章公開貼文／操作紀錄</td><td>Relay</td><td>刪除後停止對外提供；底層附加式簽章紀錄保留（見「你的權利」）</td></tr>
            <tr><td>版務紀錄</td><td>Relay</td><td>為治理與申訴目的保留</td></tr>
            <tr><td>裝置推播權杖</td><td>Relay</td><td>至裝置登出或權杖失效</td></tr>
            <tr><td>Email 與 OTP（驗證時）</td><td>Issuer（僅記憶體）</td><td>約數分鐘，驗證完成即丟棄</td></tr>
            <tr><td>重複註冊防護之雜湊承諾</td><td>Issuer</td><td>保留（不可逆，無法還原個人資料）</td></tr>
            <tr><td>護照 NFC／行動自然人憑證資料</td><td>Issuer（暫時處理）</td><td>僅於驗證過程處理，不儲存</td></tr>
            <tr><td>可驗證憑證（VC）</td><td>你的裝置錢包</td><td>由你保管；可被撤銷</td></tr>
            <tr><td>IP 位址</td><td>—</td><td>不留存</td></tr>
            <tr><td>AppView 投影內容</td><td>AppView</td><td>跟隨 Relay 公開內容；刪除會傳播</td></tr>
          </tbody>
        </table>
      </div>

      <h2>你的權利</h2>
      <ul>
        <li><strong>取用與可攜</strong>：你的公開內容皆為經你簽章的可攜格式，你可以隨時取用，或帶到其他相容的服務。</li>
        <li><strong>刪除</strong>：
          <ul>
            <li>你可以在 App 內清除本機身分（設定 → 登出此裝置），這會停止此裝置使用該身分。</li>
            <li>你刪除的內容會從 AppView 等閱讀介面移除；刪除會向下游傳播。</li>
            <li><strong>誠實聲明</strong>：Relay 上的公開貼文屬於「附加式簽章紀錄」（append-only log）。刪除會使內容停止在所有對外介面提供，但為了維持紀錄的完整性與可驗證性，底層的簽章紀錄本身會保留。</li>
            <li>完整的帳號與資料刪除請求，請來信 <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>，我們會在合理期間內處理並回覆。另見<a href="/account-deletion">刪除帳號與資料</a>。</li>
          </ul>
        </li>
        <li><strong>憑證撤銷</strong>：已核發的可驗證憑證可以被撤銷。</li>
      </ul>

      <h2>法規適用</h2>
      <p>本服務依據<strong>台灣《個人資料保護法》</strong>處理個人資料；當事人得依該法第 3 條行使查詢、閱覽、複製、補充、更正、停止處理利用及刪除等權利。對於位於歐盟／歐洲經濟區的使用者，適用 <strong>GDPR</strong>（處理之法律基礎為契約履行及你的明確同意——例如身分驗證流程）；對於美國加州使用者，適用 <strong>CCPA/CPRA</strong>——我們不出售也不分享（sell/share）個人資料。行使上述任何權利，請聯絡 <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>。</p>

      <h2>兒童</h2>
      <p>本服務不以未滿 13 歲之兒童為對象。若我們知悉在未經法定代理人同意下處理了未滿 13 歲兒童的個人資料，將儘速刪除。</p>

      <h2>政策變更</h2>
      <p>我們修改本政策時，會更新本頁的生效日期；重大變更會在服務內以明顯方式公告。持續使用本服務即表示你已閱讀更新後的政策。</p>

      <h2>聯絡我們</h2>
      <p>隱私相關問題與請求：<a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a></p>
`;

const PRIVACY_EN = `
        <h1>Privacy Policy</h1>
        <p class="legal-effective">Effective date: July 7, 2026</p>

        <p>Elix (domain elix.cool, "the Service") is a decentralized discussion community built on self-sovereign identity. Our design principle: data stays on your device wherever possible; what leaves your device is minimized, signed by you, verifiable, and portable. This policy explains what data is processed where, for how long, and what rights you have.</p>

        <h2>What we do not do</h2>
        <ul>
          <li>No analytics, tracking, or advertising SDKs, and no third-party tracking code.</li>
          <li>No per-user telemetry; operational metrics are aggregate-only and cannot be tied to an individual.</li>
          <li>We do not collect or store your location.</li>
          <li>IP addresses are not written to any persistent record.</li>
          <li>We do not sell, rent, or share personal data with third parties for marketing.</li>
        </ul>

        <h2>Where data lives</h2>

        <h3>Your device</h3>
        <ul>
          <li><strong>Identity private keys (Ed25519)</strong>: generated and stored on your device (software custody, labeled with a custody_class), and excluded from cloud backup (noBackupFilesDir on Android, file protection on iOS). Private keys never leave your device.</li>
          <li>Your local database, drafts, and the Verifiable Credentials (VCs) in your wallet.</li>
        </ul>

        <h3>Relay</h3>
        <p>The relay stores only what you choose to make public:</p>
        <ul>
          <li>Your public DID and handle.</li>
          <li>Your signed public posts and operations — an append-only, tamper-evident signed log.</li>
          <li>Moderation records.</li>
          <li>Device push tokens (used only as content-free sync hints).</li>
        </ul>
        <p>The relay stores <strong>no</strong> email, legal name, phone number, national ID, or location; IP addresses are not persisted.</p>

        <h3>Issuer (identity verification)</h3>
        <ul>
          <li>During verification, your email and one-time passcode (OTP) are held in memory for a matter of minutes, then discarded.</li>
          <li>To prevent duplicate sign-ups (Sybil resistance), only a keyed, irreversible hashed commitment is kept; it cannot be reversed into your email or identity data.</li>
          <li>Passport NFC chip data and Taiwan MobileMoica (mobile citizen certificate) data are processed transiently during verification and <strong>never stored</strong>.</li>
          <li>Issued Verifiable Credentials live only in the wallet on your device; credential revocation is supported.</li>
        </ul>

        <h3>AppView</h3>
        <p>The AppView is a read-only projection of content that is already public on the relay, used for browsing and search. It holds no additional personal data.</p>

        <h2>When data leaves your device</h2>
        <p>Only when you choose: publishing public content, going through identity verification, or enabling push notifications. Private keys and unpublished private data do not leave the device.</p>

        <h2>Retention</h2>
        <div class="legal-table-wrap">
          <table>
            <thead>
              <tr><th>Data</th><th>Where</th><th>Retention</th></tr>
            </thead>
            <tbody>
              <tr><td>Identity private keys (Ed25519)</td><td>Your device only</td><td>Until you clear the local identity or uninstall</td></tr>
              <tr><td>Public DID, handle</td><td>Relay</td><td>Life of the account (public record)</td></tr>
              <tr><td>Signed public posts / operations</td><td>Relay</td><td>Removed from serving on deletion; the underlying append-only signed log is retained (see "Your rights")</td></tr>
              <tr><td>Moderation records</td><td>Relay</td><td>Retained for governance and appeals</td></tr>
              <tr><td>Device push tokens</td><td>Relay</td><td>Until device sign-out or token expiry</td></tr>
              <tr><td>Email and OTP (during verification)</td><td>Issuer (memory only)</td><td>Minutes; discarded when verification completes</td></tr>
              <tr><td>Duplicate-prevention hashed commitment</td><td>Issuer</td><td>Retained (irreversible; cannot reveal personal data)</td></tr>
              <tr><td>Passport NFC / MobileMoica data</td><td>Issuer (transient)</td><td>Processed during verification only; never stored</td></tr>
              <tr><td>Verifiable Credentials (VCs)</td><td>Your device wallet</td><td>Held by you; revocable</td></tr>
              <tr><td>IP addresses</td><td>—</td><td>Not persisted</td></tr>
              <tr><td>AppView projection</td><td>AppView</td><td>Mirrors public relay content; deletions propagate</td></tr>
            </tbody>
          </table>
        </div>

        <h2>Your rights</h2>
        <ul>
          <li><strong>Access and portability</strong>: your public content is in a signed, portable format; you can access it at any time or take it to another compatible service.</li>
          <li><strong>Deletion</strong>:
            <ul>
              <li>You can clear your local identity in-app (Settings → Sign out this device), which stops this device from using the identity.</li>
              <li>Content you delete is removed from the AppView and other reading surfaces; deletions propagate downstream.</li>
              <li><strong>Honest note</strong>: public posts on the relay are part of an append-only signed log. Deletion removes the content from every serving surface, but the underlying signed log entries are retained to preserve the integrity and verifiability of the record.</li>
              <li>For full account and data deletion requests, email <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>; we will respond within a reasonable period. See also <a href="/account-deletion">Account &amp; data deletion</a>.</li>
            </ul>
          </li>
          <li><strong>Credential revocation</strong>: issued Verifiable Credentials can be revoked.</li>
        </ul>

        <h2>Applicable law</h2>
        <p>We process personal data under Taiwan's <strong>Personal Data Protection Act</strong>; data subjects may exercise the rights in Article 3 (inquiry, review, copies, supplementation, correction, cessation of processing/use, and deletion). For users in the EU/EEA, the <strong>GDPR</strong> applies (legal bases: performance of contract, and your explicit consent — e.g. for identity verification). For California users, the <strong>CCPA/CPRA</strong> applies — we do not sell or share personal information. To exercise any of these rights, contact <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>.</p>

        <h2>Children</h2>
        <p>The Service is not directed at children under 13. If we learn that we processed personal data of a child under 13 without the consent of a legal guardian, we will delete it promptly.</p>

        <h2>Changes to this policy</h2>
        <p>When we change this policy, we update the effective date on this page; material changes will be announced prominently in the Service. Continued use of the Service means you have read the updated policy.</p>

        <h2>Contact</h2>
        <p>Privacy questions and requests: <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a></p>
`;

// ---------------------------------------------------------------------------
// 服務條款 / Terms of Service
// ---------------------------------------------------------------------------

const TERMS_ZH = `
      <h1>服務條款</h1>
      <p class="legal-effective">生效日期：${LEGAL_EFFECTIVE_DATE_ZH}</p>

      <p>歡迎使用 Elix（網域 elix.cool，下稱「本服務」）。使用本服務即表示你同意下列條款；若不同意，請勿使用本服務。</p>

      <h2>服務說明</h2>
      <p>Elix 是一個去中心化、以自主身分為基礎的討論社群。你的身分由你裝置上的密鑰控制；你發布的公開內容由你簽章，並經由你選擇的主機（host）與聯邦網路散布。</p>

      <h2>你的帳號與金鑰</h2>
      <ul>
        <li>你的身分私鑰保存在你的裝置上，由你自行保管。請妥善保護你的裝置與復原方式。</li>
        <li>我們提供多裝置與復原機制，但若你遺失所有金鑰與復原途徑，我們可能無法為你復原身分。</li>
        <li>你對以你的身分簽章發布的所有內容與行為負責。</li>
      </ul>

      <h2>可接受使用</h2>
      <p>你同意不得利用本服務：</p>
      <ul>
        <li>從事違法行為，或發布違法內容；</li>
        <li>騷擾、威脅、恐嚇他人，或發布仇恨、煽動暴力之內容；</li>
        <li>冒充他人或不實表示與任何個人、組織之關係；</li>
        <li>大量發送垃圾訊息、操縱互動或進行協同性不實行為；</li>
        <li>企圖破壞、規避或濫用本服務之安全機制（包括身分驗證與重複註冊防護）。</li>
        <li>製作、發布、索取、散布或協助兒少性虐待及剝削（CSAE）或兒少性虐待素材（CSAM）；詳見<a href="/child-safety">兒少安全標準</a>。</li>
      </ul>

      <h2>你的內容</h2>
      <ul>
        <li><strong>所有權歸你</strong>：你保有你所創作內容的一切權利。</li>
        <li><strong>散布授權</strong>：當你發布公開內容時，你授予你所選擇的主機與聯邦網路節點一項非專屬、全球性、免權利金的授權，以儲存、傳輸、散布及顯示該內容，作為提供服務之必要。</li>
        <li>當你刪除內容，此授權就「未來的對外提供」終止；惟基於紀錄完整性，附加式簽章紀錄本身依<a href="/privacy">隱私權政策</a>所述保留。</li>
      </ul>

      <h2>版務與申訴</h2>
      <ul>
        <li>各主機（host）得依其版規對其範圍內的內容採取版務處置；處置附有理由代碼（reason code），且效力以該主機為限（host-scoped），不影響你的身分本身。</li>
        <li>你可以對版務處置提出申訴；申訴管道由各主機提供，或來信 <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>。</li>
      </ul>

      <h2>免責聲明</h2>
      <p>本服務依「現狀」及「現有」基礎提供，不附任何明示或默示之擔保，包括但不限於適售性、特定目的適用性及不侵權之擔保。我們不擔保服務不中斷、無錯誤或完全安全。</p>

      <h2>責任限制</h2>
      <p>於法律允許之最大範圍內，就因使用或無法使用本服務所生之任何間接、附隨、衍生、懲罰性損害或利益損失，我們不負賠償責任。若依法不得排除責任，我們的總責任以你於請求發生前十二個月內就本服務支付之金額（若為免費使用，則為新台幣零元）為上限。</p>

      <h2>終止</h2>
      <p>你可以隨時停止使用本服務並清除本機身分（見<a href="/account-deletion">刪除帳號與資料</a>）。若你重大違反本條款，主機得於其範圍內限制或終止對你提供服務。</p>

      <h2>準據法與管轄</h2>
      <p>本條款以中華民國（台灣）法律為準據法。因本條款所生之爭議，雙方同意以台灣台北地方法院為第一審管轄法院。</p>

      <h2>條款變更</h2>
      <p>我們修改本條款時，會更新本頁生效日期；重大變更會在服務內公告。變更生效後繼續使用本服務，即視為同意修改後之條款。</p>
`;

const TERMS_EN = `
        <h1>Terms of Service</h1>
        <p class="legal-effective">Effective date: July 7, 2026</p>

        <p>Welcome to Elix (domain elix.cool, "the Service"). By using the Service you agree to these terms; if you do not agree, do not use the Service.</p>

        <h2>The Service</h2>
        <p>Elix is a decentralized discussion community built on self-sovereign identity. Your identity is controlled by keys on your device; public content you publish is signed by you and distributed through the hosts and federation you choose.</p>

        <h2>Your account and keys</h2>
        <ul>
          <li>Your identity private keys are stored on your device and held by you. Protect your device and your recovery paths.</li>
          <li>We provide multi-device and recovery mechanisms, but if you lose all keys and recovery paths we may be unable to recover your identity for you.</li>
          <li>You are responsible for all content and actions published under your signed identity.</li>
        </ul>

        <h2>Acceptable use</h2>
        <p>You agree not to use the Service to:</p>
        <ul>
          <li>engage in unlawful activity or publish unlawful content;</li>
          <li>harass, threaten, or intimidate others, or publish hateful content or incitement to violence;</li>
          <li>impersonate any person or misrepresent your affiliation with any person or organization;</li>
          <li>send bulk spam, manipulate engagement, or engage in coordinated inauthentic behavior;</li>
          <li>attempt to break, circumvent, or abuse the Service's security mechanisms (including identity verification and duplicate-signup prevention).</li>
        <li>create, publish, request, distribute, or facilitate child sexual abuse and exploitation (CSAE) or child sexual abuse material (CSAM); see the <a href="/child-safety">Child Safety Standards</a>.</li>
        </ul>

        <h2>Your content</h2>
        <ul>
          <li><strong>You keep ownership</strong>: you retain all rights to the content you create.</li>
          <li><strong>Distribution license</strong>: when you publish public content, you grant the hosts and federation nodes you choose a non-exclusive, worldwide, royalty-free license to store, transmit, distribute, and display that content as necessary to operate the Service.</li>
          <li>When you delete content, this license ends for future serving; the append-only signed log itself is retained as described in the <a href="/privacy">Privacy Policy</a>.</li>
        </ul>

        <h2>Moderation and appeals</h2>
        <ul>
          <li>Each host may take moderation actions on content within its scope under its own rules; actions carry a reason code and are host-scoped — they do not affect your identity itself.</li>
          <li>You may appeal moderation actions through the host's appeal channel, or by emailing <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>.</li>
        </ul>

        <h2>Disclaimers</h2>
        <p>The Service is provided "as is" and "as available", without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose, and non-infringement. We do not warrant that the Service will be uninterrupted, error-free, or fully secure.</p>

        <h2>Limitation of liability</h2>
        <p>To the maximum extent permitted by law, we are not liable for any indirect, incidental, consequential, or punitive damages, or loss of profits, arising from your use of or inability to use the Service. Where liability cannot be excluded, our total liability is capped at the amount you paid for the Service in the twelve months before the claim (zero for free use).</p>

        <h2>Termination</h2>
        <p>You may stop using the Service and clear your local identity at any time (see <a href="/account-deletion">Account &amp; data deletion</a>). A host may restrict or terminate service within its scope if you materially breach these terms.</p>

        <h2>Governing law and venue</h2>
        <p>These terms are governed by the laws of the Republic of China (Taiwan). Disputes arising from these terms shall be subject to the jurisdiction of the Taipei District Court, Taiwan, as the court of first instance.</p>

        <h2>Changes to these terms</h2>
        <p>When we change these terms, we update the effective date on this page; material changes will be announced in the Service. Continued use after changes take effect constitutes acceptance of the updated terms.</p>
`;

// ---------------------------------------------------------------------------
// 關於 / About
// ---------------------------------------------------------------------------

const ABOUT_ZH = `
      <h1>關於 Elix</h1>
      <p class="legal-effective">elix.cool</p>

      <p>Elix 是一個去中心化、身分自主的討論社群。你的身分由你裝置上的密鑰控制，而不是由某個平台的帳號資料庫決定；你發布的內容由你簽章、可驗證、可攜帶，並經由你選擇的主機與聯邦網路散布。</p>

      <p>我們的原則很簡單：資料盡可能留在你的裝置上；社群治理公開、附理由、可申訴；沒有追蹤、沒有廣告、沒有演算法暗箱。</p>

      <ul>
        <li><a href="/privacy">隱私權政策</a></li>
        <li><a href="/terms">服務條款</a></li>
        <li><a href="/account-deletion">刪除帳號與資料</a></li>
        <li><a href="/child-safety">兒少安全標準</a></li>
        <li><a href="/support">支援中心</a></li>
      </ul>
`;

const ABOUT_EN = `
        <h1>About Elix</h1>

        <p>Elix is a decentralized discussion community built on self-sovereign identity. Your identity is controlled by keys on your device rather than a platform's account database; the content you publish is signed by you, verifiable, portable, and distributed through the hosts and federation you choose.</p>

        <p>Our principles are simple: data stays on your device wherever possible; community governance is transparent, reason-coded, and appealable; no tracking, no ads, no algorithmic black boxes.</p>

        <ul>
          <li><a href="/privacy">Privacy Policy</a></li>
          <li><a href="/terms">Terms of Service</a></li>
          <li><a href="/account-deletion">Account &amp; data deletion</a></li>
          <li><a href="/child-safety">Child safety standards</a></li>
          <li><a href="/support">Support</a></li>
        </ul>
`;

// ---------------------------------------------------------------------------
// 支援中心 / Support
// ---------------------------------------------------------------------------

const SUPPORT_ZH = `
      <h1>Elix 支援中心</h1>
      <p class="legal-effective">${SUPPORT_CONTACT_EMAIL}</p>

      <p>需要 Elix 的使用協助、想回報問題，或有 App Store 相關問題時，請來信：</p>
      <p><a href="mailto:${SUPPORT_CONTACT_EMAIL}">${SUPPORT_CONTACT_EMAIL}</a></p>

      <h2>開始使用</h2>
      <ul>
        <li>你可以先在 Web 閱讀公開看板與討論。</li>
        <li>帳號建立、身分與錢包功能會在 Elix App 提供；Web 不會要求你交出私鑰。</li>
        <li>想了解身分、同步、隱私與簽章標示，請閱讀 <a href="/#/about">認識 Elix</a>。</li>
      </ul>

      <h2>回報問題時請告訴我們</h2>
      <ul>
        <li>使用的平台與 App／瀏覽器版本。</li>
        <li>你正在做什麼，以及問題發生的時間。</li>
        <li>畫面上的錯誤訊息或截圖；請勿寄送私鑰、護照號碼、身分證號或驗證碼。</li>
      </ul>

      <h2>隱私、帳號與資料刪除</h2>
      <p>隱私權問題與資料權利請參閱<a href="/privacy">隱私權政策</a>。若要提出完整的帳號與資料刪除請求，請依<a href="/account-deletion">刪除帳號與資料</a>頁面的方式聯絡 <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>。</p>

      <h2>兒少安全</h2>
      <p>Elix 對兒少性虐待及剝削採取零容忍立場。請參閱<a href="/child-safety">兒少安全標準</a>，並使用 App 內檢舉功能或來信 ${SUPPORT_CONTACT_EMAIL} 回報疑似違規內容。</p>
`;

const SUPPORT_EN = `
        <h1>Elix Support</h1>
        <p class="legal-effective">${SUPPORT_CONTACT_EMAIL}</p>

        <p>For help using Elix, bug reports, or App Store questions, contact:</p>
        <p><a href="mailto:${SUPPORT_CONTACT_EMAIL}">${SUPPORT_CONTACT_EMAIL}</a></p>

        <h2>Getting started</h2>
        <ul>
          <li>You can read public boards and discussions on the web.</li>
          <li>Account creation, identity, and wallet features are provided in the Elix app; the web never asks for your private key.</li>
          <li>For identity, sync, privacy, and signature labels, read <a href="/#/about">About Elix</a>.</li>
        </ul>

        <h2>When reporting a problem</h2>
        <ul>
          <li>Tell us your platform and app or browser version.</li>
          <li>Describe what you were doing and when the problem occurred.</li>
          <li>Include an error message or screenshot when useful. Never send private keys, passport or national-ID numbers, or verification codes.</li>
        </ul>

        <h2>Privacy, accounts, and data deletion</h2>
        <p>See the <a href="/privacy">Privacy Policy</a> for privacy questions and data rights. For a full account and data deletion request, follow the <a href="/account-deletion">Account &amp; data deletion</a> page and contact <a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a>.</p>

        <h2>Child safety</h2>
        <p>Elix has zero tolerance for child sexual abuse and exploitation. See the <a href="/child-safety">Child Safety Standards</a>, and report suspected violations through the in-app Report feature or to ${SUPPORT_CONTACT_EMAIL}.</p>
`;

// ---------------------------------------------------------------------------
// 刪除帳號與資料 / Account & data deletion
// ---------------------------------------------------------------------------

const DELETION_ZH = `
      <h1>刪除帳號與資料</h1>
      <p class="legal-effective">生效日期：${LEGAL_EFFECTIVE_DATE_ZH}</p>

      <p>本頁說明如何刪除你的 Elix 帳號與相關資料，以及刪除後各系統中的資料會發生什麼事。</p>

      <h2>在 App 內刪除</h2>
      <ol>
        <li>打開 Elix App，進入「<strong>設定</strong>」。</li>
        <li>選擇「<strong>登出此裝置</strong>」，並確認「<strong>清除本機身分</strong>」。這會停止此裝置使用該身分；裝置上的私鑰隨本機身分清除而移除。</li>
        <li>若要刪除個別內容，直接在 App 內刪除該貼文即可——刪除會傳播到 AppView 等閱讀介面。</li>
      </ol>

      <h2>刪除後，各系統的資料會如何處理</h2>
      <ul>
        <li><strong>你的裝置</strong>：本機身分（含私鑰）與本機資料被清除。</li>
        <li><strong>AppView（閱讀介面）</strong>：你刪除的內容會被移除，不再顯示。</li>
        <li><strong>Relay</strong>：你的公開貼文屬於「附加式簽章紀錄」（append-only log）。刪除會使內容停止在所有對外介面提供，但為維持紀錄完整性與可驗證性，底層簽章紀錄本身會保留。詳見<a href="/privacy">隱私權政策</a>。</li>
        <li><strong>Issuer（身分驗證）</strong>：驗證過程本來就不儲存你的 email、護照或自然人憑證資料；僅存在的不可逆雜湊承諾無法還原為個人資料。已核發的憑證可以撤銷。</li>
      </ul>

      <h2>完整資料刪除請求</h2>
      <p>若你希望我們處理完整的帳號與資料刪除（包括撤銷已核發的憑證、移除推播權杖等伺服器端資料），請以你註冊時可驗證的方式來信：</p>
      <p><a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a></p>
      <p>請在信中註明你的 handle 或 DID。我們會在合理期間內處理並回覆。</p>
`;

const DELETION_EN = `
        <h1>Account &amp; Data Deletion</h1>
        <p class="legal-effective">Effective date: July 7, 2026</p>

        <p>This page explains how to delete your Elix account and related data, and what happens to data in each system after deletion.</p>

        <h2>Delete in the app</h2>
        <ol>
          <li>Open the Elix app and go to <strong>Settings</strong>.</li>
          <li>Choose <strong>Sign out this device</strong> and confirm <strong>Clear local identity</strong>. This stops the device from using the identity; the private keys on the device are removed along with the local identity.</li>
          <li>To delete individual content, delete the post in the app — the deletion propagates to the AppView and other reading surfaces.</li>
        </ol>

        <h2>What happens to your data</h2>
        <ul>
          <li><strong>Your device</strong>: the local identity (including private keys) and local data are cleared.</li>
          <li><strong>AppView (reading surfaces)</strong>: content you delete is removed and no longer displayed.</li>
          <li><strong>Relay</strong>: your public posts are part of an append-only signed log. Deletion removes the content from every serving surface, but the underlying signed log entries are retained to preserve the integrity and verifiability of the record. See the <a href="/privacy">Privacy Policy</a>.</li>
          <li><strong>Issuer (identity verification)</strong>: verification never stores your email, passport, or citizen-certificate data in the first place; the only retained artifact is an irreversible hashed commitment that cannot be reversed into personal data. Issued credentials can be revoked.</li>
        </ul>

        <h2>Full data deletion requests</h2>
        <p>If you want us to process a full account and data deletion (including revoking issued credentials and removing server-side data such as push tokens), email us in a way we can verify against your registration:</p>
        <p><a href="mailto:${PRIVACY_CONTACT_EMAIL}">${PRIVACY_CONTACT_EMAIL}</a></p>
        <p>Include your handle or DID. We will process the request and respond within a reasonable period.</p>
`;

// ---------------------------------------------------------------------------
// 兒少安全 / Child safety
// ---------------------------------------------------------------------------

const CHILD_SAFETY_ZH = `
      <h1>兒少安全標準</h1>
      <p class="legal-effective">生效日期：${LEGAL_EFFECTIVE_DATE_ZH}</p>

      <p>Elix 對兒少性虐待及剝削（CSAE）與兒少性虐待素材（CSAM）採取零容忍立場。本標準適用於 Elix 第一方服務所提供、代管或顯示的公開內容與互動功能。</p>

      <h2>禁止內容與行為</h2>
      <p>你不得使用 Elix 製作、發布、索取、散布、宣傳、協助或以其他方式促成下列內容或行為：</p>
      <ul>
        <li>任何 CSAE 或 CSAM；</li>
        <li>對未成年人進行性剝削、性化、誘導（grooming）、招募、交易或勒索；</li>
        <li>索取、交換或散布未成年人私密或性化影像、資訊或接觸機會；</li>
        <li>以任何方式協助、宣傳或規避與兒少性剝削有關的違法行為。</li>
      </ul>

      <h2>檢舉與聯絡</h2>
      <p>發現疑似違反本標準的公開內容時，請優先使用 App 內的「檢舉」功能，並選擇最適當的原因。你也可以寄信至 <a href="mailto:${SUPPORT_CONTACT_EMAIL}">${SUPPORT_CONTACT_EMAIL}</a>。請提供內容連結、貼文識別資訊或足以定位內容的資訊；不要以電子郵件傳送可能違法的影像或私密資料。</p>

      <h2>處理方式</h2>
      <p>我們會依風險與適用法律審查檢舉。對於可信的 CSAE／CSAM 檢舉，Elix 得採取必要措施，包括停止第一方服務對相關內容的提供、限制其在第一方服務的散布或存取、保全依法必要的紀錄，以及在適用法律要求或為保護兒少所必要時，向有權機關通報或配合調查。處置會盡量維持在必要且相稱的範圍內。</p>

      <h2>聯邦與主機範圍</h2>
      <p>Elix 是可互通的討論服務；外部主機可能有自己的規則與處理程序。本頁說明 Elix 第一方服務的標準，並不取代外部主機的責任。即使內容來自外部來源，Elix 仍可在第一方服務中採取必要的安全措施。</p>

      <h2>緊急情況</h2>
      <p>若有兒少正面臨立即危險，請先聯絡當地緊急服務或執法機關。這不是緊急通報服務。</p>
`;

const CHILD_SAFETY_EN = `
      <h1>Child Safety Standards</h1>
      <p class="legal-effective">Effective date: ${LEGAL_EFFECTIVE_DATE}</p>

      <p>Elix has zero tolerance for child sexual abuse and exploitation (CSAE) and child sexual abuse material (CSAM). These standards apply to public content and interactive features provided, hosted, or displayed by Elix first-party services.</p>

      <h2>Prohibited content and conduct</h2>
      <p>You must not use Elix to create, publish, request, distribute, promote, facilitate, or otherwise enable:</p>
      <ul>
        <li>any CSAE or CSAM;</li>
        <li>sexual exploitation, sexualization, grooming, recruitment, trafficking, or extortion of a minor;</li>
        <li>requesting, exchanging, or distributing sexualized or intimate images, information, or access involving a minor; or</li>
        <li>assisting, promoting, or evading laws concerning child sexual exploitation.</li>
      </ul>

      <h2>Reporting and contact</h2>
      <p>To report public content that may violate these standards, use the in-app <strong>Report</strong> feature and choose the most appropriate reason. You may also contact <a href="mailto:${SUPPORT_CONTACT_EMAIL}">${SUPPORT_CONTACT_EMAIL}</a>. Include a content link, post identifier, or other information that lets us locate the content; do not email potentially unlawful images or private information.</p>

      <h2>How we respond</h2>
      <p>We review reports according to risk and applicable law. For credible CSAE/CSAM reports, Elix may take necessary action, including stopping first-party serving of the content, restricting its distribution or access in first-party services, preserving records required by law, and reporting to or cooperating with competent authorities where required by applicable law or necessary to protect children. Measures are kept necessary and proportionate.</p>

      <h2>Federation and host scope</h2>
      <p>Elix is an interoperable discussion service, and external hosts may have their own rules and processes. This page describes standards for Elix first-party services and does not replace an external host's responsibility. Elix may still take necessary safety measures in its first-party services when content originates externally.</p>

      <h2>Immediate danger</h2>
      <p>If a child is in immediate danger, contact local emergency services or law enforcement first. This is not an emergency reporting service.</p>
`;

// ---------------------------------------------------------------------------
// Page registry
// ---------------------------------------------------------------------------

const PAGES = Object.freeze({
  '/privacy': {
    titles: { 'zh-Hant': '隱私權政策', en: 'Privacy Policy' },
    bodies: { 'zh-Hant': PRIVACY_ZH, en: PRIVACY_EN },
  },
  '/terms': {
    titles: { 'zh-Hant': '服務條款', en: 'Terms of Service' },
    bodies: { 'zh-Hant': TERMS_ZH, en: TERMS_EN },
  },
  '/about': {
    titles: { 'zh-Hant': '關於 Elix', en: 'About Elix' },
    bodies: { 'zh-Hant': ABOUT_ZH, en: ABOUT_EN },
  },
  '/support': {
    titles: { 'zh-Hant': 'Elix 支援中心', en: 'Elix Support' },
    bodies: { 'zh-Hant': SUPPORT_ZH, en: SUPPORT_EN },
  },
  '/account-deletion': {
    titles: { 'zh-Hant': '刪除帳號與資料', en: 'Account & Data Deletion' },
    bodies: { 'zh-Hant': DELETION_ZH, en: DELETION_EN },
  },
  '/child-safety': {
    titles: { 'zh-Hant': '兒少安全標準', en: 'Child Safety Standards' },
    bodies: { 'zh-Hant': CHILD_SAFETY_ZH, en: CHILD_SAFETY_EN },
  },
});

// Returns { title, html } for a legal-page pathname, or null when the path is
// not a legal page (the server then continues to the SPA/asset pipeline).
// Trailing slashes are tolerated (`/privacy/` → `/privacy`) so pasted store
// URLs never 404 on a slash.
export function renderLegalPage(pathname, { locale = DEFAULT_LOCALE } = {}) {
  const normalized = String(pathname ?? '').replace(/\/+$/, '') || '/';
  const page = PAGES[normalized];
  if (!page) return null;

  const resolvedLocale = resolveLegalLocale(locale);
  const title = page.titles[resolvedLocale] ?? page.titles[DEFAULT_LOCALE];

  return {
    title: `${title} · Elix`,
    html: layout({
      path: normalized,
      title,
      body: localizeLegalBodyLinks(
        page.bodies[resolvedLocale] ?? page.bodies[DEFAULT_LOCALE],
        resolvedLocale,
      ),
      locale: resolvedLocale,
    }),
  };
}
