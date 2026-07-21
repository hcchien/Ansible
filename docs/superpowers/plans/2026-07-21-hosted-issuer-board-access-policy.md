# Hosted Issuer 與 Credential-Gated Boards Implementation Plan

> **Status:** proposed — 尚未開始實作
> **Scope:** Issuer、Wallet、Relay／Forum Host、AppView、mobile／desktop app、營運與金鑰治理
> **Primary scenario:**「時代力量」不需自行部署 Issuer，由 Elix 代管簽發黨員 VC；只有持有有效黨員 VC 的使用者能發現、讀取或參與指定討論區。

## Goal

建立一套不要求組織自行維運伺服器、但仍不把組織主權交給 Elix 的 Hosted Issuer；同時讓 Board 擁有明確、版本化且可稽核的 Access Policy，將 VC 驗證結果轉成短效、board-scoped capability，而不是全域身分標籤。

完成後應支援：

1. 組織在 app 內開啟代管、建立管理員與簽章治理規則。
2. Hosted Issuer 使用 tenant 專屬、不可匯出的 KMS／HSM operational key 簽發 VC。
3. 組織 root authority 授權或撤銷 hosted operational key，搬離代管服務時不必更換 issuer identity。
4. 使用者透過 Wallet 申請、接收、保存、出示及撤銷／更新 VC。
5. 建板者在建立或編輯 Board 時設定 discovery、read、post、moderation 與 federation policy。
6. Forum Host 驗證最少必要 claim、VC status 與 holder binding，簽發短效 board capability。
7. 會員資格只影響指定 Board，絕不自動升級為 `verified_human` 或任何全域 reputation tier。
8. 沒有網路時，使用者仍能讀取已合法下載的本機資料、撰寫草稿；需要重新驗證的受保護網路操作延後至上線後完成。

## Non-goals

- 不讓 passkey 直接簽 VC；passkey 僅證明管理操作的 user presence／verification。
- 不把 Relay、AppView 或 Forum Host 當作 Wallet，也不把完整 VC 永久存進這些服務。
- 不宣稱未加密的 credential-gated board 具內容機密性。
- 不承諾撤銷後可刪除其他裝置已下載或已解密的資料。
- 第一階段不支援匿名投票、可轉讓會員資格、跨組織 reputation aggregation 或自動真人認證。
- 第一階段不讓第三方任意 credential schema 直接執行程式碼；只接受版本化、白名單的 policy operators。

## Source Context

實作前必讀：

- `docs/superpowers/specs/2026-05-24-tris-aura-engineering-constitution-design.md`
- `docs/superpowers/specs/2026-05-24-engineering-constitution-compliance-review.md`
- `docs/superpowers/plans/2026-06-12-trust-gated-boards.md`
- `docs/superpowers/plans/2026-07-21-webauthn-sync-capability.md`
- `docs/superpowers/plans/2026-07-21-wallet-reputation-sync-and-user-presence.md`

現有程式邊界：

- Issuer 單一金鑰與簽發流程：
  - `ansible_issuer/go/cmd/server/main.go`
  - `ansible_issuer/go/internal/vc/issuer.go`
  - `ansible_issuer/go/internal/vc/model.go`
  - `ansible_issuer/go/internal/api/handler.go`
- Board schema、signed intent 與 enforcement：
  - `ansible_relay/phoenix/lib/ansible_relay/db/forum_host_board.ex`
  - `ansible_relay/phoenix/lib/ansible_relay/forum_host/signed_intent.ex`
  - `ansible_relay/phoenix/lib/ansible_relay/forum_host/store.ex`
  - `ansible_relay/phoenix/lib/ansible_relay/forum_host/posting_gate.ex`
  - `ansible_relay/phoenix/lib/ansible_relay/web/controllers/forum_host_controller.ex`
  - `ansible_relay/phoenix/lib/ansible_relay/web/controllers/ops_controller.ex`
- App board creation與 projection：
  - `ansible_node/app/lib/widgets/board_form_dialog.dart`
  - `ansible_node/app/lib/services/forum_host_client.dart`
  - `ansible_core/store/lib/src/entities/hosted_board_projection.dart`
- Wallet／VP：
  - `ansible_node/app/lib/services/oid4vp_request.dart`
  - `ansible_node/app/lib/services/oid4vp_presentation_service.dart`
  - `ansible_node/app/lib/services/vc_presentation_service.dart`
  - `ansible_node/app/lib/screens/wallet_verifier_consent_screen.dart`
  - `ansible_node/app/lib/services/relay_reputation_presentation_service.dart`

## Constitution Review

### Identity and credential control

- VC 私鑰與 holder credential 留在使用者 Wallet；Relay／Forum Host 只取得一次性 presentation 與必要 verification result。
- Hosted Issuer operational key 必須是 tenant 專屬、不可匯出，且由組織 root authority 明確 delegation；Elix 不應成為組織的永久 root of trust。
- Root authority 建議由至少 `2-of-3` 組織管理員 Wallet 控制。若採單一管理員或完全託管 root key，UI 與 API 必須標示為 reduced-trust mode。
- 現行 DID 私鑰仍有 raw key custody 的已知缺口。高敏感會員憑證正式上線前，管理員 root key 與 holder binding key 必須完成 hardware-backed custody 或通過明確的 reduced-trust security review。

### Data minimization and privacy

- VC 僅包含 Board decision 必要 claims，例如 `membership=true`、`organization_id`、`membership_class`、有效期限；不得放入姓名、身分證號、黨員編號原文或 provider assertion，除非另有明確且可撤回的用途同意。
- Issuer 資料庫預設只保留 credential identifier/hash、type、issuer tenant、時間、status、policy snapshot 與 approver；申請證明原件應使用短 retention 或不落盤。
- Presentation 使用 pairwise holder identifier、nonce、audience 與 domain binding，避免不同 Board／Host 之間可被動關聯。
- Log、metrics、error response 不得包含完整 VC、raw claim、legal identity 或 presentation token。

### Local-first and user agency

- Board entitlement 不得刪除 Wallet VC、本機貼文或已下載內容。撤銷只阻止未來 server access、publish 與新 encryption epoch key。
- Offline 可讀既有本機資料、建立本機草稿；不得為了遠端授權而阻止本機 create/list/read。
- 使用者能匯出 Wallet、Issuer delegation/audit record 與組織設定；組織能更換 Hosted Issuer provider。

### Trust, governance, and ranking

- 組織會員 VC 只能產生 board-scoped entitlement；不得寫入 `did_accounts.reputation_tier`，也不得顯示成全域真人或可信度徽章。
- Board policy 與 trusted issuers 必須在加入前可讀，拒絕必須回傳 reason code，敏感 policy downgrade 必須版本化並經門檻核准。
- Forum Host 可制定自己的 Board policy，但 app 必須顯示 host compliance、資料可見性與是否加密，讓使用者可理解並退出。

### Constitution verdict

設計方向符合 user-controlled identity、minimal disclosure、local-first 與 board-level governance；但「政治組織會員憑證正式上線」有兩個 blocking gates：hardware-backed 管理員／holder key custody，以及私密 Board 的端對端／群組金鑰設計完成安全審查。在此之前只能推出清楚標示 host-visible 的 public-read／credential-post 模式。

## Architecture and Trust Boundaries

```text
Organization root admins (2-of-3 Wallet keys)
        | sign IssuerKeyDelegation / policy approvals
        v
Hosted Issuer tenant ---- Cloud KMS/HSM operational key
        | OID4VCI offer + credential
        v
User Wallet (private VC + holder key)
        | OID4VP, minimum disclosure, nonce/audience bound
        v
Forum Host policy verifier ---- status / issuer delegation resolution
        | short-lived board capability
        v
Board discovery/read/write APIs

AppView: public content only; protected/private board content is excluded.
Relay: transport and host boundary; never becomes the credential Wallet.
```

### Key roles

- **Organization root authority:** stable issuer governance identity；授權 operational key、credential types、期限與 approval policy。
- **Hosted Issuer:** multi-tenant control plane、OID4VCI、workflow、status、audit；不持有組織 root key。
- **Operational signer:** KMS/HSM 內 tenant-specific key；只能依 delegation 與 workflow 簽允許的 credential。
- **Wallet:** VC 唯一預設保存位置、OID4VCI client、OID4VP presenter、holder-binding key owner。
- **Forum Host:** Board policy authority與 verifier；驗證後發短效 capability。
- **Relay:** signed ops、同步與 host routing；不得把會員 VC 轉成全域 reputation。
- **AppView:** 只 projection 可公開索引的內容；不得 ingest hidden/private Board。

## Canonical Data Contracts

所有 JSON 必須有 `version`、canonical serialization、strict schema validation 與未知安全關鍵欄位 fail-closed 行為。

### IssuerKeyDelegation v1

```json
{
  "type": "IssuerKeyDelegation",
  "version": 1,
  "issuer": "did:elix:org:ntp",
  "delegate_key": "did:key:z...",
  "service": "https://issuer.elix.cool/tenants/ntp",
  "credential_types": ["PoliticalPartyMembershipCredential"],
  "not_before": "2026-08-01T00:00:00Z",
  "expires_at": "2027-08-01T00:00:00Z",
  "approval_policy": {"threshold": 2, "administrators": 3},
  "sequence": 4
}
```

Delegation 由 root threshold signatures 核准。`sequence` 防止舊 delegation rollback；撤銷發布新的高序號 delegation/status，而不是刪除歷史。

### PoliticalPartyMembershipCredential v1

```json
{
  "type": ["VerifiableCredential", "PoliticalPartyMembershipCredential"],
  "issuer": "did:elix:org:ntp",
  "credentialSubject": {
    "id": "did:peer:board-specific-holder",
    "organization_id": "did:elix:org:ntp",
    "membership": true,
    "membership_class": "member"
  },
  "validFrom": "...",
  "validUntil": "...",
  "credentialStatus": {"type": "BitstringStatusListEntry", "...": "..."}
}
```

`membership_class` 是選配；Board 不需要時不得要求揭露。Credential 必須 holder-bound、短期有效且可查 status。

### BoardAccessPolicy v1

```json
{
  "version": 1,
  "discovery": "credential_required",
  "read": {"requirement": "member"},
  "post": {"requirement": "member"},
  "moderate": {"requirement": "moderator"},
  "requirements": {
    "member": {
      "credential_type": "PoliticalPartyMembershipCredential",
      "trusted_issuers": ["did:elix:org:ntp"],
      "claims": [{"path": "membership", "op": "equals", "value": true}],
      "holder_binding": "required",
      "status": {"required": true, "max_age_seconds": 300}
    }
  },
  "capability_ttl_seconds": 300,
  "content_visibility": "host_visible",
  "federation": "disabled"
}
```

第一版 policy operators 僅允許 `equals` 與有限 enum membership；禁止 regex、script 或任意 JSONPath。`content_visibility` 只允許：

- `public`: 可公開 projection／federation。
- `host_visible`: Host 能讀內容，AppView 與 federation 排除；不能宣稱私密。
- `end_to_end_encrypted`: 僅在 Encryption Phase 完成後啟用。

### BoardAccessCapability v1

短效 token 必須綁定：`subject/pairwise holder`、exact Forum Host audience、`board_id`、`policy_version`、scopes (`discover/read/post/moderate`)、`jti`、`iat`、`exp`。它不是 VC、不是 login session、不可跨 Board／Host 使用，也不可替代每筆 ops 的 DID content signature。

## Database Changes

### Issuer PostgreSQL

新增 migration 與 tenant-scoped repositories：

- `issuer_tenants`: organization DID、service slug、mode、status、policy version。
- `issuer_administrators`: admin DID、role、state；不存 raw passkey secret。
- `issuer_admin_credentials`: WebAuthn credential ID、COSE public key、sign count、transports。
- `issuer_admin_challenges`: single-use、expiry、origin/RP binding。
- `issuer_admin_capabilities`: hashed opaque token、scope、tenant、expiry、revoked_at。
- `issuer_signing_keys`: KMS key resource、public key、algorithm、state、version；沒有 private key bytes。
- `issuer_key_delegations`: canonical payload、hash、root signatures、sequence、validity、state。
- `credential_templates`: schema/type、claim allowlist、retention、approval workflow、version。
- `issuance_requests`: applicant pairwise DID、payload hash、state、policy snapshot、expiry。
- `issuance_approvals`: request、admin/automation delegation、decision、signed intent hash。
- `credential_records`: credential ID/hash/type、subject pairwise hash、issued/expiry/status index；不存完整 VC。
- `issuer_status_lists`: list version、purpose、published URI、KMS signature metadata。
- `issuer_audit_events`: append-only event、actor、request hash、policy version、timestamp。
- `issuer_automation_delegations`: source adapter、allowed template、rate/expiry、public key、sequence。

每次 query 必須顯式 tenant scope；integration tests 需證明跨 tenant ID enumeration 仍不可讀寫。若資料庫支援，production 加 PostgreSQL RLS 作第二層防線。

### Relay／Forum Host PostgreSQL

`forum_host_boards` 新增：

- `access_policy jsonb NOT NULL DEFAULT open-policy`
- `access_policy_version bigint NOT NULL DEFAULT 1`
- `content_visibility text NOT NULL DEFAULT 'public'`
- `federation_policy jsonb NOT NULL DEFAULT public-compatible policy`

新增：

- `forum_host_board_policy_versions`: canonical policy、hash、actor、approvals、effective_at、superseded_at。
- `forum_host_board_access_grants`: hashed capability ID、pairwise subject hash、board、policy version、scopes、expiry、revocation reason；短 retention。
- `forum_host_verification_nonces`: single-use OID4VP nonce、audience、board、policy version、expiry。
- Encryption Phase 才新增 `forum_host_board_key_epochs` 與 wrapped-key delivery metadata；不得存 plaintext epoch key。

原有 `posting_policy.min_post_tier` 保留以相容舊 Board，但 evaluator 規則為：舊 policy 只限制發文；`access_policy` 不得暗中寫入或提升 reputation tier。

## API and Protocol Surface

### Hosted Issuer administration

- `POST /api/v1/hosted-issuers` — 建 tenant draft。
- `POST /api/v1/hosted-issuers/{tenant}/admin/webauthn/register/options|verify`
- `POST /api/v1/hosted-issuers/{tenant}/admin/webauthn/authenticate/options|verify`
- `POST /api/v1/hosted-issuers/{tenant}/keys` — 建 KMS operational key proposal。
- `POST /api/v1/hosted-issuers/{tenant}/delegations` — 上傳 root-signed delegation。
- `POST /api/v1/hosted-issuers/{tenant}/delegations/{id}/activate|revoke`
- `GET /api/v1/hosted-issuers/{tenant}/manifest` — public keys、delegation chain、metadata、status endpoints。
- `GET /api/v1/hosted-issuers/{tenant}/audit/export`

Issuer admin capability audience/scope 必須和 Relay `sync:write` capability 完全分離；不可共用 token secret、audience 或 endpoint。

### OID4VCI

實作 standards-compatible metadata、credential offer、authorization/pre-authorized code、nonce/proof、credential endpoint 與 status publication。第一版可先支援 app-mediated authorization code flow；pre-authorized code 必須 single-use、短效且要求 holder proof，不得以 URL 本身當永久憑證。

### Board policy and OID4VP

- `createBoard v2` 包含完整 policy；v1 一律映射為 open/public legacy defaults。
- 新增獨立 `updateBoardPolicy v1` signed intent，包含 `board_id`、`previous_policy_hash`、`new_policy`、`effective_at` 與 approvals；不可用一般 `updateBoard` 繞過 threshold。
- `GET /api/v1/forum-host/boards/{id}/access-requirements`
- `POST /api/v1/forum-host/boards/{id}/presentation/options`
- `POST /api/v1/forum-host/boards/{id}/presentation/verify` → short-lived board capability。
- 所有 protected discovery/read/write endpoint 驗證 capability audience、scope、board、policy version、expiry；write 仍另驗 DID-signed op。

統一 reason codes：`credential_required`、`credential_expired`、`credential_revoked`、`issuer_not_trusted`、`claim_not_satisfied`、`holder_binding_failed`、`policy_changed`、`capability_expired`、`board_hidden`。Response 與 log 不回傳實際 sensitive claim。

## Implementation Phases

每一 phase 先寫 failing tests，再做最小實作；每個服務的 feature flag、migration rollback 與 backward compatibility 都必須在同一 phase 完成。

### Phase 0 — Protocol specs, threat model, and launch gates

- [ ] 新增 `docs/protocol/hosted_issuer_v1.md`：delegation、tenant、admin approval、OID4VCI profile、status 與 migration/export。
- [ ] 新增 `docs/protocol/board_access_policy_v1.md`：schema、canonicalization、evaluation order、capability、reason codes、offline semantics。
- [ ] 新增 privacy data inventory 與 retention table；逐欄標記 service ownership、encryption、retention、export/delete 行為。
- [ ] 新增 threat model：tenant escape、KMS confused deputy、admin takeover、replay、delegation rollback、malicious schema/policy、status rollback、correlation、capability theft與 federation leakage。
- [ ] 做 Cloud KMS algorithm／latency／quota spike，確認 Ed25519 或選定標準演算法與 VC proof suite；結果寫入 ADR，不允許靜默 fallback 到 raw hex production key。
- [ ] 定義 security gates：hardware-backed admin/holder key、external cryptographic review、private board encryption review。

**Exit criteria:** canonical test vectors跨 Go/Elixir/Dart 得到相同 hash；security/privacy review 接受資料流；演算法與 KMS provider 決策完成。

### Phase 1 — Refactor Issuer into signer and tenant boundaries

- [ ] 在 `ansible_issuer/go/internal/vc` 抽出 `Signer` interface（public key、algorithm、sign、key ID）；保留 software signer 僅供 tests/local dev。
- [ ] 新增 GCP KMS signer adapter、fake signer 與錯誤分類；production config 禁止 `ISSUER_PRIVATE_KEY_HEX`。
- [ ] 建立上述 tenant migrations、repository interface 與 mandatory tenant context。
- [ ] 將現有 first-party issuer 遷移成 bootstrap tenant，不改變現有 credential verification。
- [ ] 所有 audit event append-only；credential payload、raw claims與 private key 不得進 log。
- [ ] 測試 signer contract、KMS transient error/idempotency、tenant isolation、legacy migration與 config fail-closed。

**Exit criteria:** 同一套 issuer tests 可跑 software fake/KMS contract；production 啟動時若無有效 KMS/delegation 即拒絕簽發。

### Phase 2 — Hosted onboarding and organization governance

- [ ] 實作 tenant draft、admin invitations、roles（owner/issuer/reviewer/auditor）與 threshold policy。
- [ ] 實作 Issuer 專用 WebAuthn enrollment/assertion及最長五分鐘 `issuer_admin:*` capability。
- [ ] 建立 KMS key proposal；由 root admins 在 Wallet 確認 canonical delegation hash並 threshold-sign。
- [ ] activate/revoke/rotate delegation；驗證 sequence、validity、credential type allowlist與 KMS public key match。
- [ ] 建立 manifest、audit timeline、export與 provider migration bundle。
- [ ] App 新增 Hosted Issuer setup wizard、管理員 approval inbox、key/delegation status與 reduced-trust warning。
- [ ] 測試少於 threshold 不生效、舊 delegation replay失敗、撤銷後不可新簽、rotation不中斷舊 VC verification。

**Exit criteria:** 三名管理員可用 2-of-3 啟用 tenant，Elix operator 無 root signature 無法新增簽章權限；組織能匯出並撤銷 hosted delegation。

### Phase 3 — Credential templates, issuance workflow, and Wallet OID4VCI

- [ ] 實作 template allowlist、claim minimization、approval workflow與 immutable policy snapshot。
- [ ] 實作 OID4VCI metadata、offer、holder proof、credential issuance與 Wallet client。
- [ ] 建立 membership application adapter interface；輸入必須簽章、具 replay protection、template/claim/rate/expiry 限制。
- [ ] 敏感組織預設人工 threshold approval；bulk automation需獨立 delegation且可立即撤銷。
- [ ] 實作 Bitstring Status List publication、suspend/revoke/reissue，並處理 cache max-age與 rollback protection。
- [ ] Wallet 顯示 issuer、用途、claims、有效期、status與 holder binding；使用者明確同意後保存。
- [ ] 測試 duplicate/retry idempotency、offer replay、wrong holder proof、policy change mid-flight、revocation與最少 claim persistence。

**Exit criteria:** 使用者可從 app 完成 offer → consent → VC 入 Wallet；Issuer DB 無完整 VC／原始黨員資料；撤銷狀態可被獨立 verifier 正確解析。

### Phase 4 — Board Access Policy storage and authoring

- [ ] Relay migration加入 policy欄位、版本歷史與 open legacy defaults。
- [ ] 新增 Elixir policy schema/parser/canonicalizer/evaluator；未知 version/operator fail closed。
- [ ] `createBoard v2` 與 `updateBoardPolicy v1` signed intent；一般 metadata update 不得改 access policy。
- [ ] 定義敏感變更：新增 trusted issuer、降低 read/post gate、`host_visible/encrypted → public`、啟用 federation；需 board governance threshold approval與延遲生效。
- [ ] `hosted_board_projection.dart`、`forum_host_client.dart` 和 local SQLite/Drift projection帶 policy version/hash，但不存 presentation token。
- [ ] 將 `board_form_dialog.dart` 改成 Board Policy Wizard：公開範圍、誰能讀／發文／管理、可信 issuer、status、federation與資料可見性摘要。
- [ ] 顯示 human-readable policy diff、風險警告與回復前一版本入口；不把進階 JSON 暴露為預設 UI。
- [ ] 測試 v1 client compatibility、strict validation、stale hash conflict、threshold與 downgrade delay。

**Exit criteria:** 新舊 app 都可讀 open Board；新 app 能建立 credential-post Board；沒有 verifier 前，credential-read/hidden options保持 feature-flag disabled。

### Phase 5 — OID4VP verification and board capabilities

- [ ] 建立 Forum Host verifier module，解析 issuer manifest/delegation、VC proof、holder binding、nonce/audience、claims與 status freshness。
- [ ] 不重用 `relay_reputation_presentation_service.dart` 的 reputation mutation；新增獨立 `board_access_presentation_service.dart`。
- [ ] 產生最少 disclosure OID4VP request；Wallet consent畫面顯示 Board、Host、揭露 claims、用途與 capability TTL。
- [ ] 驗證成功後簽發 opaque/HMAC 或 asymmetric board capability，資料庫只存 hash與必要 audit metadata。
- [ ] 將 gate放在所有 authoritative chokepoints：protected board discovery、board detail、thread listing/read、attachment fetch、thread/reply/moderation writes。
- [ ] Client-side gate僅作 UX；server始終 authoritative。policy version變更或 status revocation使舊 capability失效。
- [ ] Offline 行為：已下載內容照常讀；草稿照常建；publish queue標記 `authorization_required`，上線重新取得 capability後才送出。
- [ ] 測試跨 Board、跨 Host、跨 subject、過期、replay、stale policy、revoked VC、offline queue與 DID signature仍必須有效。

**Exit criteria:** `public-read + credential-post` 可在 dev 端到端運作；會員 VC 不改 reputation tier；錯誤均 reason-coded且不洩漏 claims。

### Phase 6 — Protected discovery/read without false privacy claims

- [ ] 支援 `credential_required` discovery：匿名 list/search不回傳 Board metadata；使用者可透過 invitation/organization directory啟動 VP。
- [ ] 支援 `host_visible` credential-gated read；UI 顯著說明 Forum Host仍可讀內容，且內容不進 AppView／public search／federation。
- [ ] Relay與AppView contract tests證明 protected board/thread/post不被 projection、feed、search、notification preview或analytics payload洩漏。
- [ ] Attachment storage採相同 capability gate與 cache-control；CDN URL短效且不可公開猜測。
- [ ] 本機資料保留遵守 local-first：取消資格後不刪除已下載資料，但 UI 顯示無法再同步與其原因。

**Exit criteria:** 未持 credential者無法從 API/search/AppView得知 hidden Board；具 credential者可用短效 capability read；產品文案不稱此模式端對端加密。

### Phase 7 — End-to-end encrypted private boards

- [ ] 先另寫專門 cryptographic design與外部 security review；未通過前 `end_to_end_encrypted` 永遠 disabled。
- [ ] 每個 Board 使用 epoch group content key；Host只保存 ciphertext與 wrapped key metadata。
- [ ] VP成功後，key service將當前 epoch key包裝給 holder的 board-scoped hardware-backed public key。
- [ ] 新增/撤銷會員與重大 compromise觸發 epoch rotation；撤銷只阻止未來 epoch，清楚揭露無法回收既有 plaintext。
- [ ] Client本地加解密 thread/post/attachment，明文不得進 Relay/AppView/log/notification payload。
- [ ] 處理多裝置新增、裝置撤銷、備份/recovery與local-first key custody；不得靠 Host保存可解密 root secret。
- [ ] property/fuzz/interop tests及第三方 security review。

**Exit criteria:** Host資料庫與object storage compromise不能解密內容；撤銷者拿不到新 epoch；多裝置與recovery不破壞使用者資料主權。

### Phase 8 — Operations, observability, abuse prevention, and migration

- [ ] Terraform/Cloud Run/KMS IAM採最小權限：service account只能對指定 tenant key sign，不能 export/delete root authority。
- [ ] 建立 key rotation、compromise、tenant suspension、status outage、restore與provider exit runbooks。
- [ ] Metrics只使用 aggregate counts/reason codes；禁止 DID、credential ID、claims 成為 metric labels。
- [ ] Tenant rate limits、approval velocity alerts、automation kill switch、KMS quota/backpressure與idempotency keys。
- [ ] 備份/restore驗證 delegation/status/audit一致性；restore不得回滾 sequence/status版本。
- [ ] 管理員與使用者資料匯出、tenant關閉、retention purge及法規請求流程。
- [ ] Dev/staging/prod使用不同 RP ID、KMS projects/keys、issuer DIDs、origins與databases；不可讓 dev delegation 在 prod 成立。

**Exit criteria:** disaster recovery drill、tenant isolation test、key compromise drill與privacy log audit通過。

## Mobile/Desktop UX Deliverables

### Organization / Hosted Issuer

- 「建立組織」→ 選擇 delegated hosted custody／BYOK／reduced-trust。
- 邀請管理員、設定 threshold、建立 operational key、在每位管理員裝置核准 delegation。
- Credential template builder只顯示安全欄位，提供用途與retention摘要。
- Application/approval inbox顯示 canonical request hash、policy version、已核准人數；高風險操作要求passkey。
- Key status、delegation expiry、audit timeline、export/migrate與emergency revoke。

### Board creation/edit

- Step 1 基本資料；Step 2 發現與讀取；Step 3 發文/管理資格；Step 4 trusted issuer/credential；Step 5 federation/privacy；Step 6 review與threshold approval。
- 預設仍為公開、任何人可讀寫，維持既有行為；選會員限制時提供 preset，避免使用者手寫 claims。
- Board header與join gate顯示「由誰簽發」、「需要揭露什麼」、「Host是否能讀」、「是否可聯邦」、「資格失效會怎樣」。
- Policy變更以diff顯示；降低保護的變更有冷卻期與既有會員通知。

### Wallet / access

- Credential offer consent、Wallet card、status/expiry、renew/revoke guidance。
- Access request consent每次清楚顯示 verifier/Board/claims/purpose/TTL；允許取消且不影響本機資料。
- Offline狀態分清楚：「本機可讀」、「等待重新驗證後同步」、「資格已失效但本機備份仍保留」。

## Verification Matrix

### Go / Issuer

- Unit: canonical payload、delegation sequence/threshold、template allowlist、retention sanitizer、signer contract。
- Integration: PostgreSQL tenant isolation、WebAuthn challenge replay、KMS fake/real dev key、OID4VCI flows、status rollback。
- Security: operator無root approval、tenant A不能使用tenant B key、raw claims/private key永不出現在logs。

### Elixir / Relay and Forum Host

- Unit: strict policy parser、evaluation/reason codes、capability scope/audience/version、issuer delegation resolver。
- Integration: discovery/read/write所有chokepoints、ops DID signature + capability雙重驗證、policy change/revocation、attachment gate。
- Leakage: protected data不進AppView、search、feeds、notifications、federation與metrics。

### Dart / Flutter and local store

- Unit: OID4VCI/OID4VP parsing、minimum disclosure selection、policy projection、offline queue state。
- Widget: setup wizard、threshold approval、Board Policy Wizard、consent、reason-coded recovery、host-visible warning。
- E2E: organization setup → issue membership VC → create gated Board → nonmember denied → member admitted → revoke → local data retained/new sync denied。

### Required adversarial scenarios

- Stolen capability used on another Board/Host/device/DID。
- Old policy/delegation/status list replay。
- Malicious Issuer asks Wallet for excessive claims。
- Forum Host attempts to turn membership VC into global reputation。
- AppView or federation crawler requests protected content。
- Admin account/passkey compromised但未達threshold。
- KMS/Issuer unavailable while user is offline。
- Organization migrates provider; old credentials remain verifiable while new issuance switches keys。

## Rollout Strategy

1. **Dev alpha:** Issuer multi-tenancy、KMS delegation、OID4VCI與 Wallet；不接 Board enforcement。
2. **Internal beta:** `public-read + credential-post`；會員 VC只產生board capability，功能旗標限測試組織。
3. **External beta:** `host_visible credential-read`；AppView/federation leakage suite、privacy review與營運runbook通過。
4. **Production low-risk credentials:** 社團會員、活動工作人員等；明確標示key custody與Host visibility。
5. **High-sensitivity organizations:** hardware-backed admin/holder keys、threshold governance、legal/privacy review完成後才開放政治/工會/醫療等類別。
6. **Encrypted boards:** Phase 7 security review通過後另行上線，不能與host-visible模式混稱。

每階段都能以 server feature flag 停止新 issuance／新 capability，不刪 Wallet VC、本機內容或既有 signed ops。Schema migration採 additive-first；舊 client看到未知 protected Board時fail closed並提示升級。

## Definition of Done

- 組織不需自行部署 server即可建立Hosted Issuer，但沒有root threshold delegation時Elix不能擅自簽發。
- Production signing key不可匯出、每個tenant隔離、可輪替/撤銷/遷移，完整audit可匯出。
- 使用者可用OID4VCI取得最少claim、holder-bound、可撤銷的會員VC，且完整VC只在Wallet。
- 建板流程可設定版本化Board Access Policy；敏感downgrade需治理核准，舊Board行為不變。
- Forum Host以OID4VP驗證後只發短效board-scoped capability；會員VC不改全域reputation。
- Protected content不洩漏至AppView/search/federation；offline本機資料與草稿不因資格撤銷而刪除。
- `host_visible`與`end_to_end_encrypted`的保證在UI/API/documentation均不混淆。
- Go、Elixir、Dart unit/integration/E2E、跨語言canonical vectors、安全與災難演練全部通過。
- 政治組織正式上線前，hardware-backed custody與private board cryptographic review兩個launch gates均已完成。
