# Elix S1–S5 / U1–U5 修正與驗證紀錄

> 後續已補上独立 checkpoint、持久撤銷與首次觀察驗證，原 S1 限制由[撤銷與時間回填修正結果](2026-09-07-elix-authority-witness-results.md)更新；最新測試為 AppView 87、Relay 491、Flutter 78。

日期：2026-09-07。使用者 resume 後完成本機修改與以下測試。未 commit、未部署。原始稽核保留作為修正前證據；本文件記錄修正後狀態，不能以原 probe 的舊結果描述目前程式。

## Constitution Review

已讀工程憲章與 compliance review。本次沿用裝置持有身分金鑰、獨立作者驗章、使用者明確同意與可逆公開授權的約束；不把歷史作者簽章因現在撤銷而追溯改寫。不宣稱整個 Elix 已全面合規，也不以本機測試代替實機與正式環境驗收。

## 修正內容

| 項目 | 已實作與回歸範圍 |
|---|---|
| S1 | AppView 獨立驗 self-certifying DID 與 genesis/rotation/recovery chain，按簽署內容時間選金鑰 epoch；缺失或過期 anchor 拒絕。WebAuthn 驗實際 assertion、UV、origin/RP、DID 簽署 delegation、credential/attestation 綁定、operation/content hash 與完整投影一致性。記錄真正驗過的作者公鑰；canonical DID 僅採用 dual-signed migration。舊 host receipt 不再充當作者授權。新送件的到期、撤銷與重播由 Relay 阻擋；歷史重建與 freshness 限制見下。 |
| S2 | Android legacy backup、cloud backup、device transfer 都使用實際 `file` domain 排除 ansible.db 與 WAL/SHM。XML 回歸涵蓋三種路徑。 |
| S3 | 一般 Wallet OID4VP 生產入口新增可信 did:web issuer 的 Ed25519 Data Integrity 真驗章及即時狀態查詢；未知／失敗狀態拒絕。VP signer 使用 active identity key，支援硬體 P256 與明確軟體 Ed25519，不再讀舊 raw key。Go 真實 issuer 與 OpenSSL P256 fixtures 驗證跨實作編碼。 |
| S4 | 同意畫面先準備不可變的實際完整憑證／VP，揭露額外屬性及可關聯風險；核准前重驗同一憑證及狀態。五分鐘期限、單次使用、簽前／簽後金鑰綁定檢查。同源 HTTPS 接收方限制，禁止 direct_post 跟隨轉址；取消不簽署也不 POST。 |
| S5 | 備份紀錄按 DID＋演算法＋公鑰 epoch 隔離；區分產生與使用者確認保存，不宣稱復原演練完成。重新產生清除舊保存確認，拒絕跨身分標記；硬體身分仍拒絕匯出 raw key。 |
| U1 | 真正的公開內容搜尋與 Discover（人、板、文章），支援 Enter、編碼與 XSS 防護、來源部分失敗提示；桌面／手機 Discover、Boards、通知可達。AppView Explore 補上 thread。 |
| U2 | 首頁、左右欄與看板目錄都標示公開看板，移除偽「已訂閱」宣告；區分看板規則與使用者登入／資格。 |
| U3 | QR 旁提供同機開啟 Elix 與安裝協助，深連結核對 scheme、path、challenge 及已設定 Relay origin。登入後回原頁／搜尋；更新只教掃 QR 的舊引導。 |
| U4 | 隱私與權限文案說明私人預設本機、主動公開內容可被索引／轉載、瀏覽器有限授權；補上編輯、刪除、reaction 等權限說明。 |
| U5 | 320/390/1440px 實際 DOM 與畫面檢查；手機導覽 11px／48px 高，頁尾 12px、連結 28.5px 高；FAB 深色圖示，深色模式對比 7.98:1、淺色 token 對比 4.64:1。PK pill 實測 37.84px，沒有拉成 579px 全欄。修復登入後 320px header 溢出及較長看板規則擠壓名稱。 |

舊 Web Passkey 缺少 DID 簽署的 attestation 綁定時，不允許新發文。App 的「設定 → 同步 → 展開 Relay → 更新網頁 Passkey 授權」提供明確重新登記入口，Web 錯誤也引導至此。重新登記會經過使用者確認與系統 Passkey 流程，測試未操作真實帳號。

## 測試結果

| 測試 | 結果 |
|---|---|
| Web `npm test` | 130 個成功輸出，exit 0；新增公開搜尋／深連結／看板語義回歸 |
| Flutter 10 個相關測試檔 | 49 tests passed，exit 0 |
| Flutter 本次 10 個 implementation 檔 analyze | No issues found，exit 0 |
| AppView `mix test` 全套 | 77 passed，exit 0 |
| Relay `mix test` 全套 | 491 passed，exit 0 |
| `git diff --check` | 通過 |

Flutter 範圍：android_backup_policy、wallet_credential_verifier、oid4vp_request、oid4vp_presentation_service、vc_presentation_service、wallet_verifier_consent_screen、recovery_readiness_store、identity_backup_screen、sync_capability_service、sync_settings_screen。未宣称 Flutter 整個 repository 的所有測試都已執行。

Relay/AppView 使用獨立 localhost:55437 PostgreSQL 測試庫；測試完成後已正常停止專用 PostgreSQL 與本機預覽伺服器，瀏覽器 viewport 已還原。新增 Relay migration `20260907000000_bind_web_credential_authority` 已在隔離庫成功套用。所有測試 identity/key/credential 都是合成樣本；fixtures 不包含私鑰。舊 AppView arbitrary DID/random-key 測試樣本已改成真實自認證、簽章及 dual-signed migration，production 沒有測試 bypass。

測試紀錄：`evidence/2026-09-07-elix/remediation-final/`。UI 使用實際前端程式與合成 API 回應；搜尋、QR handoff URL、核准返回都在本機執行，不是正式環境或真實手機系統的登入驗證。已保存 `mobile-board-390.png`、`mobile-search-390.png`、`mobile-search-320.png`、`desktop-board-1440.png`。

## 安全相依套件

安裝新驗證依賴時 Hex 發現既有安全公告，已在原版本限制內更新鎖檔：Bandit 1.12.5、HPAX 1.0.4、Plug 1.20.3、Postgrex 0.22.4；Relay 另升級 Ecto 3.14.2／Ecto SQL 3.14.0、Decimal 3.1.1、Mint 1.10.0，以及其相容依賴。最終 Hex resolver 未再回報這批已知公告。更新後重跑 Relay／AppView 全套通過。這不是所有語言／所有依賴的全面漏洞掃描。

## 必須保留的限制與發布順序

1. **S1 後續更新：已加入獨立權限見證。** 原先仅靠歷史簽章無法判別來源隱藏狀態與時間回填的缺口，已透過 App 直接聯絡 AppView、持久 checkpoint／撤銷與精確操作觀察補上。完整信任範圍、測試與新版發布順序見[後續結果](2026-09-07-elix-authority-witness-results.md)。不宣稱多方透明日誌或惡意 AppView 抵抗。
2. Receipt 只保存接收資訊，不授予作者權限，也不認定其自帶金鑰或 `accepted_at` 為可信時間證明。未知 receipt key 不會讓假的 author proof 通過。
3. **發布順序已由上述後續結果更新，需先暫停 ingest 並建立 witness／重驗舊資料。** 原相容性前提仍需先套 Relay migration 並更新 Relay／原生 enrollment，再更新 AppView 與 Web；需在 staging 確認既有 DID chain、舊 Passkey 更新流程及索引重建。無證據的 legacy did:plc 等路徑會 fail closed，不能直接把這次鎖檔／驗證修改單獨部署到舊 Relay。
4. 尚未做 Android 雲端備份實際抽取、iOS/Android/desktop 真硬體 Passkey／VP 出示或換機復原演練；這些不能由 XML、Widget 或 OpenSSL fixture 測試取代。
5. Wallet 目前支援明確的 Elix did:web issuer／Ed25519 DI／同源 status 格式；未支援的 proof、數字 canonicalization（非整數或超過安全整數）及未知狀態會拒絕，不會退回語法驗證。

工作區保留原有政府憑證與其它未提交變更；未 stage、reset、commit、push、deploy。初始 tracked diff 備份仍在 `/private/tmp/elix-before-remediation.patch`。
