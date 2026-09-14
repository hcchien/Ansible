# Elix PD1–PD8 實作與驗證紀錄

日期：2026-09-14。基準：`a846fb40`（1.0.12）。

後續發布更新：prod 三個服務已部署，1.0.13 (2026091401) 已成功上傳 TestFlight；Apple 回覆處理中。詳見 [1.0.13 發布紀錄](2026-09-14-elix-1.0.13-release.md)。下文保留實作完成時的驗證邊界。
分支：`codex/product-flow-remediation`。狀態：本機實作完成，尚未部署、打包或送審。
原始工作區的 Wallet／Issuer 等未提交修改未納入本次工作樹。

## 使用者可見結果

| 項目 | 實作結果 | 主要驗證 |
|---|---|---|
| PD1 原文入口 | App／Web 的 note、murmur 有精確詳情及分享網址；公開討論不必先訂閱；通知可回讀本機缺少的原文；載入失敗可重試，留言失敗保留已讀正文 | exact route／proxy、匿名全文及回覆、受限／刪除篩選、分頁測試；Web 桌面及 320px 視覺檢查 |
| PD2 傳送狀態 | 設定 → 同步 → 傳送中心，依項目區分本機保存、待授權、待傳送、失敗、Relay 接收；單項重試、未嘗試項目停止傳送、可主動複製去敏診斷 | 取消授權後重開佇列、同 operation ID 重試、409 衝突不誤報成功、取消與簽署競爭、已嘗試項目不能誤稱收回 |
| PD3 草稿 | 討論／投票、回覆、murmur 與內嵌留言保存裝置本機草稿；按帳號／目標隔離，提供繼續或丟棄；提交到本機資料庫後才清除 | debounce 前返回、儲存重開、投票／mentions 還原、帳號隔離；還原不簽署或發布 |
| PD4 信任說明 | 移除沒有機器人等絕對承諾；作者簽章與真人資格用不同標示及可開啟說明，Web 原文也說明來源完整性不保證事實正確 | 原文信任說明與 UI 測試／瀏覽器點擊 |
| PD5 匿名瀏覽 | 一般新安裝可先看公開內容，互動時轉身分建立，完成後保留原內容脈絡 | credential-free onboarding、匿名原文及註冊接續測試 |
| PD6 閱讀範圍 | Following 不再用 Explore 填補；本機搜尋清楚標示裝置範圍，主動進入公開搜尋才送出關鍵字；公開搜尋按提交執行 | 既有本機搜尋、discovery client 及公開讀取測試 |
| PD7 復原導引 | 分清舊手機核准、遺失手機復原、授權瀏覽器及內容備份；不把身分復原當作私密資料還原或並行原生多裝置 | 復原導引 320px widget 測試 |
| PD8 Relay 社群讀取 | 原生社群查詢改用所選 Relay；Relay 自有查詢不依賴 AppView，Web 仍使用 AppView；profile／handle 有短 TTL 與來源隔離 | Relay 完整回歸、端點契約、撤銷／刪除／受限資料篩選及顯示名稱快取測試 |

舊 note／murmur 補送保留作者的原始 createdAt／publishedAt，操作建立時間與 Relay 接收時間另存。
簽章徽章保留明確驗證旗標；只有 author DID 並不自動升格為已驗證。
傳送中心的列表及診斷有數量上限；發送去重使用完整作者操作歷史，不受列表顯示範圍限制。
停止尚未嘗試的操作不刪除本機內容，也不聲稱能收回曾經傳出的副本。
可選外部分發結果仍在同步設定中按目標呈現，與 Relay 接收分開。

## Constitution Review

已閱讀工程憲章及目前 compliance review。維持裝置金鑰保管、本機優先、帳號隔離及受限資料 fail-closed；草稿恢復不代表公開或簽署同意。診斷只記操作識別、時間、服務主機與規範化原因，匯出附目前 App build，不含正文、私鑰、token、憑證或關係清單。

Relay 是使用者選定的最新狀態與可用性來源，不宣稱偵測惡意 Relay 隱藏未見更新。AppView 的獨立證據驗證、撤銷與防回滾路徑保留。原生公開查詢 DTO 的 `sig_verified` 表示 Relay 接收及目前權限檢查結果，並不是本次新增的客戶端完整歷史密碼學驗證；原生既有同步驗證路徑未被改成僅信任這個旗標。

Relay 公開查詢會折疊同作者或已完成遷移作者的歷史更新，回傳最新原始 signed payload 與呈現 payload 作區分；私密、未知保護看板、父文已刪除或不可讀的回覆不進入結果。直接網址允許 unlisted，探索／搜尋不列入。

## 自動測試與視覺驗證

| 檢查 | 本次結果 |
|---|---|
| `flutter analyze --no-pub` | 無問題 |
| App 本次受影響驗收（18 個測試檔） | 84 通過 |
| App 其餘回歸（明確排除下列 9 個既有失敗檔） | 734 通過、1 略過；包含上述受影響測試，數量不相加 |
| 匿名新手入口單項 | 1 通過 |
| 分享 URL 建立／解析契約 | 6 通過；新 note／murmur hash identity 測試另 1 個通過 |
| core domain timeline source | 6 通過，包含缺少驗證旗標不得升格 |
| core store 全套 | 187 通過 |
| Relay 全套 | 503 通過 |
| AppView 全套 | 96 通過 |
| Web `npm test` | 全套通過 |
| Web 本機實際 renderer fixture | 桌面及 320px 原文、留言、簽章說明可讀；不是正式站或原生實機驗收 |

測試使用隔離 PostgreSQL（55438）、測試 DB 及本機 fixture，沒有修改正式資料。

### 原本已失敗的 App 測試

同一環境另外跑乾淨 1.0.12 工作樹 `/private/tmp/elix-relay-viewer-fix`，重現以下 9 個測試檔的失敗／逾時：

- `ai_setup_flow_test.dart`
- `board_policy_draft_test.dart`
- `elix_content_sharing_test.dart`（widget 操作；URL 單元契約另測）
- `home_shell_sync_test.dart`
- `i18n_compose_path_test.dart`
- `moderation_rendering_test.dart`
- `notifications_screen_test.dart`
- `report_flow_test.dart`
- `widget_test.dart`（一般首頁；匿名入口另測）

原始全套記錄 22 個具名案例失敗及後續檔案逾時；有測試期待與現有 compact UI 不符、非同步本機資料尚未到達就斷言的情形。這些尚未修完，不能把本次結果說成 App 全套綠燈。新加入的測試平台儲存 mock 不會提前初始化 widget binding，避免影響需要真實 loopback HTTP 的純單元測試；相關 SRS 下載測試 2 個通過，reaction 授權取消的回歸也已修正並通過。

暫存完整紀錄：`/private/tmp/elix-product-flutter-baseline.log`、`elix-product-flutter-regression.log`、`elix-product-acceptance-last.log`、`elix-product-relay-verified.log`、`elix-product-appview-final.log`、`elix-product-web-final.log`、`elix-product-store-final.log`（皆位於 `/private/tmp`）。不把這些暫存紀錄當成永久 CI 成果。

## 發布順序及尚待驗收

1. 先部署 Relay migration `20260914000000_add_public_read_index` 及公開讀取 API。migration 為既有 ops 增加 STORED 解碼欄與索引，可能持有資料表鎖；正式資料量下的 migration 時間與查詢容量仍需部署前量測。不要先讓 App 指向尚未提供這些 API 的 Relay。
2. 部署 AppView 的 note／murmur 精確內容 API，再部署 Web 路由及 proxy。
3. 驗證 production endpoints 後再建立／上傳新 App。本次沒有更動版號、取代商店送審或推送 prod。
4. 實機驗收：背景終止後草稿恢復、裝置授權取消／通過、斷網再重開後單篇重試、復原導引及較大字級；停用 AppView 並用裝置網路紀錄確認原生社群仍正常。這些尚未宣稱完成。
5. Relay 外部閱讀只顯示其經驗證 ActivityPub inbox 與明確 `PUBLIC_EXTERNAL_SOURCES_JSON` 清單中的來源，另要求公開看板且 `external_inclusion=true`。設定格式例如 `[{"actor_uri":"https://remote.example/users/a","board_id":"hosted-board-id"}]`。來源未設定時回空外部 lane；既有 AppView outbox-only 歷史不會自動搬移。若要保留同一批外部歷史，需在發布前確認來源清單及 Relay 收件／回填策略，不能透過代理 AppView 假裝已移除依賴。

整體狀態為本機功能修改與上述範圍測試完成，仍有既有全套 App 測試、正式容量與實機發布驗收工作。
