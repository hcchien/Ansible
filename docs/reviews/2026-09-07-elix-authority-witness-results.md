# Elix：撤銷隱藏與時間回填防護

日期：2026-09-07。接續使用者要求，一起補上 S1 原先列出的狀態新鮮度與時間回填缺口。本機實作與下列測試完成；未 commit、未部署，沒有操作正式帳號。

## Constitution Review

已讀工程憲章與 compliance review。作者權限仍源自裝置持有的身分金鑰；AppView 只獨立記錄公開授權的觀察順序，不持有身分私鑰、不接收私人內容。歷史作者簽章不因現在撤銷被抹除。這不是全系統合規或多方透明日誌的宣告。

## 已實作

| 威脅／行為 | 修正後 |
|---|---|
| Relay 隱藏已撤銷的 Web Passkey | App 以目前 root key 簽署撤銷，直接送到設定的 AppView。收到確認後才聯絡 Relay；撤銷在 AppView 永久保留。Relay 回傳舊 delegation 不能使其復活。 |
| 舊私鑰簽新內容並回填舊時間 | 第一次觀察使用 AppView 已確認的目前金鑰及伺服器時間。已非目前金鑰、已過期或已撤銷 delegation 拒絕，不能靠 payload 時間通過。 |
| Relay 回傳有效但過時的鏈 | DID checkpoint 只能沿已確認鏈前進；回滾或分叉拒絕。App 直接核對 AppView 回應，來源無法代替確認。 |
| 原始歷史重播／索引重建 | 持久化 DID＋op ID、原始簽署內容摘要及驗證過的作者資料。完全相同的已見證操作保留；相同 ID 改內容拒絕。重建不清除 authority 表。 |
| 舊資料從未被新見證者看過 | 明確「重新驗證本機公開歷史」：目前 root key 簽署確切操作摘要、AppView origin、nonce 與現在時間。保留原始簽章，標記 owner_revalidated；不假裝過去已見證。只取本機已送出的 public/unlisted 紀錄，不下载 Relay 內容代簽。 |
| 撤銷／輪替與首次觀察同時發生 | 同 DID 的資料庫交易共用 advisory lock，形成確定的先後順序；migration 目標授權另外鎖住讀取，避免輪替競態。 |
| 回填 recovery 時間跳过等待／隱藏 veto | AppView 自己開始 72 小時觀察等待；多次 recovery 不能借用第一段等待。root／已授權裝置簽署的 veto 直接送到 AppView 並永久保留。 |
| 回填 migration 時間借用舊 root | 新觀察的 canonical DID 投影需來源與目標目前 root 的雙簽，否則保留原作者 DID。 |
| 網路故障或沒有設定 AppView | 不顯示撤銷完成。AppView 失敗不繼續 Relay 撤銷；AppView 已確認但 Relay 失敗，保留紀錄供重試，既有撤銷不取消，立即清除舊 capability 快取。未設定 observer 的版本提供明確訊息。 |

新增原生入口位於「設定 → 同步 → 展開 Relay」：撤銷此裝置的網頁授權、重新驗證本機公開歷史。撤銷範圍是這台安裝曾記錄的 credential；同一 Passkey 同步到其他裝置的副本也會失效，其他不同 credential 不受影響。舊版未留下登記 ID 的授權不能由此清單憑空恢復，畫面會要求原登記裝置處理。

AppView 新增 `/api/v1/authority/checkpoint`、`/revoke`、`/veto`、`/revalidate`。網路入口不接受呼叫者提供的觀察時間；測試中的可注入時鐘只用於重現真實 WebAuthn fixture 當時的觀察。

## 測試與證據

| 驗證 | 結果 |
|---|---|
| AppView `mix test` 全套 | 87 passed，含 10 個新增 witness 測試 |
| Relay `mix test` 全套 | 491 passed |
| Flutter 15 個相關測試檔 | 78 passed |
| Flutter 本次 5 個 implementation 檔 analyze | No issues found |
| AppView 三個 migration | 隔離 PostgreSQL 成功套用 |
| 部署腳本 | `bash -n` 通過；替代 gcloud 的本機 mock 驗證新建／更新 migration job 及 service 都收到 observer origin／暫停 ingest 設定；未執行實際部署 |
| `git diff --check` | 通過 |

包含：真實 Relay WebAuthn 簽章 fixture、隱藏撤銷、舊金鑰回填時間、過期授權、相同 ID 改內容、鏈回滾、HTTP root 簽章拒絕、其他 observer origin／替換歷史內容拒絕、HTTP 歷史重驗後立即重試索引、重建保留見證、真實不同 DB connection 的輪替競態、recovery 等待／veto／連續 recovery，以及舊 migration root。

Flutter 範圍：android_backup_policy、wallet_credential_verifier、oid4vp_request、oid4vp_presentation_service、vc_presentation_service、wallet_verifier_consent_screen、recovery_readiness_store、identity_backup_screen、sync_capability_service、sync_settings_screen、authority_witness_client、relay_anchor_client、relay_identity_bootstrap_service、relay_identity_client、identity_anchor_service。這不是所有 Flutter 測試或實機驗收。

紀錄位於 `evidence/2026-09-07-elix/authority-witness/`。測試使用 localhost:55437 的隔離 PostgreSQL，所有 fixture 身分與 credential 都是合成資料，沒有私鑰輸出。先前 Web 130 個成功輸出仍見原修正報告；本輪未改 Web，未重新執行該套測試。

## 信任範圍

此修正防禦惡意 Relay，前提是 App 直接聯絡的已設定 AppView 及其持久化資料庫可信，且相關輪替／撤銷已獲 AppView 確認。離線尚未送達的撤銷不是已生效；首次加入見證者之前被來源隱藏的歷史，也不能憑空證明。

這不是多見證者 quorum、外部時間公證或 Byzantine 透明日誌；若 AppView 同樣惡意、與 Relay 串通，或安全資料庫被回滾，這個單一見證者保證不成立。公開內容仍可能被第三方保留；撤銷授權不等於刪除所有公開副本。

本次 recovery 等待保護針對可獨立驗證的 root／device 簽署 recovery chain。既有只由 Relay 驗證的一次性 recovery-code ceremony 沒有可供 AppView 獨立驗證的舊權限轉移證明，仍會被嚴格索引拒絕，未擅自把 Relay 接受視為作者授權。不要把本次測試解讀成 recovery-code 換機實機驗收。

## 發布／資料遷移順序

1. 先備份現有 DB，依原修正報告完成 Relay 的 delegation migration／author-proof 相容更新。保留原始內容；不得將舊 firehose 全部豁免驗章。
2. AppView 套用 `20260907010000`、`20260907011000`、`20260907012000` migrations，設定 `APPVIEW_PUBLIC_ORIGIN` 為對外 HTTPS origin。先以 `START_INGEST=false` 暫停新攝取。部署腳本要求 `APPVIEW_HOST`，也把這些必要設定傳給 migration job。未設定 origin 的 prod release 會拒絕啟動。
3. 原生版設定 `ANSIBLE_APPVIEW_BASE_URL`，origin 必須與 AppView 的設定一致。經使用者的身分登記／輪替流程直接建立 checkpoint；空 URL 是本機／未索引模式，不是以 Relay 代替見證者。既有使用者需更新網頁 Passkey 授權；登記現在會保存本機 credential ID 供撤銷。
4. 使用者明確確認本機已送出的公開歷史。已收到且暫緩的操作保存在 `authority_pending` 的 ID／摘要；重驗成功立即重試相同內容。未到達的歷史在後續載入時驗證，不能以此畫面聲稱全站內容已索引。
5. 在 staging 確認既有 DID chain、rotation、裝置 recovery、撤銷失敗重試、公開歷史及重建後，再恢復 ingest／按部署維護流程重建投影。沒有證據的操作維持拒絕與 rejection metrics。沒有完成 owner revalidation 的歷史不可宣稱可無損遷移。
6. `authority_frontiers`、`authority_revocations`、`authority_observations` 必須持久化與備份，不能像 feed projection 一樣丟棄重建。若遺失或回滾，先恢復可信安全狀態；禁止自動從不可信 Relay 重新初始化。

本次只準備程式、migration、部署設定與測試，不包含正式 DB migration、發布或實機身份操作。原工作區其他變更均保留。
