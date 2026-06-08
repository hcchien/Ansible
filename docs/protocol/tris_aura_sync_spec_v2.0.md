# Tris-Aura Sync Protocol Spec v2.0

> Status: Active compatibility/target spec; implementation is partial
> Supersedes: [`tris_aura_sync_spec_v1.1.md`](./tris_aura_sync_spec_v1.1.md)  
> Owners: core, identity, sync

---

## 0. Federation Direction Note

This spec describes the current AT Protocol / `did:plc`-shaped implementation
and remains valid for existing tests, local identity flow, and compatibility
work. It should not be read as the only long-term public federation path.

The new federation direction is defined in
[`tris_aura_federation_strategy_v0.1.md`](./tris_aura_federation_strategy_v0.1.md):
Ansible keeps a local-first canonical model, projects public content directly
to Nostr relays from the app, and delegates ActivityPub federation to the relay
layer. Existing `did:plc` references remain implementation context until they
are replaced or bridged.

Current code does not implement the full live PLC directory, global atproto
Firehose subscription, GCP Pub/Sub handoff, or Phoenix AppView aggregator
described later in this document. The implemented AT/PLC slice is a
compatibility path: local-shaped PLC context, XRPC `createRecord`,
`resolveHandle`, signature validation, OpStore append, and stub CID behavior.
Treat Firehose/AppView sections as target architecture unless a later document
or test explicitly marks them implemented.

Forum board ownership is also moving out of the local-canonical model. Forum
Hosts own discussion boards, threads, posts, permissions, moderation, and the
distribution FE state. Local `Board` rows are compatibility projections until
they are bound to `(forumHostId, hostedBoardId)` through
`HostedBoardProjection`/`BoardSubscription`, or replaced by `LocalCollection`
for purely local personal grouping. `murmur` and `note` remain local-owned
content and may be projected to selected Forum Hosts.

---

## 1. 核心設計哲學

| 原則 | 說明 |
|---|---|
| 身分主權 (Self-Sovereign Identity) | 採用 AT Protocol 的 DID 體系 (did:plc / did:web)，使用者掌控金鑰 |
| 在地優先 (Local-first) | 資料首存於本地 App SQLite Repo，再同步至 PDS / Firehose |
| 互操作性 (Interoperability) | 兼容 atproto 生態；使用者名稱可透過 DNS Handle 驗證 |
| 無密碼化 (Passwordless) | 全面採用 Passkeys (WebAuthn) 進行帳號建立與設備授權 |

---

## 2. 兩段式操作概覽

| | Phase 1 — Identity Anchoring | Phase 2 — Daily Operations |
|---|---|---|
| 觸發時機 | 首次使用 / 金鑰輪換 | 每次發文 / 編輯 |
| 認證方式 | Passkeys (WebAuthn) + PLC 目錄註冊 | Ed25519 Lexicon 簽章 |
| 耗時 | ~1–3 秒（網路往返） | <10 ms（本地簽章） |
| 手機耗電 | 低 | 極低 |

---

## 3. Phase 1 — Identity Anchoring (Passkeys + did:plc)

```
App                           Relay (Elixir/Phoenix)          PLC Directory
 |                                 |                               |
 |  [WebAuthn: generate keypair]   |                               |
 |  [platform key storage target; hardware custody gap remains]      |
 |                                 |                               |
 |-- POST /api/v2/identity/register                                |
 |   body: { public_key_hex, handle_suffix }                       |
 |<-- 200 OK { did_plc_op, plc_server_url }                        |
 |                                 |                               |
 |-- POST plc_server_url/create ---------------------------------->|
 |   body: { signed_genesis_op }                                   |
 |<-- 200 OK { did: "did:plc:..." } ------------------------------|
 |                                 |                               |
 |-- POST /api/v2/identity/anchor  |                               |
 |   body: {                       |                               |
 |     did: "did:plc:...",         |                               |
 |     public_key_hex: <hex>,      |                               |
 |     handle: "@user.elix.cool",|                               |
 |     registration_sig: <hex>     |                               |
 |   }                             |                               |
 |                                 |                               |
 |                   [verify registration_sig]                     |
 |                   [resolve did:plc → public key]                |
 |                   [write to DID active cache]                   |
 |<-- 200 OK { did, handle, expires_at }                           |
```

### Handle 解析

- 預設 Handle：`@{username}.elix.cool`（由 Relay 統一管理 DNS）
- 自訂 Handle：使用者在自有網域設定 DNS TXT 記錄或 HTTPS `/.well-known/atproto-did`
- Handle 解析邏輯（Rust FFI）：
  1. DNS TXT 查詢 `_atproto.{domain}` → `did={did}`
  2. 若 DNS 無記錄，嘗試 HTTPS `https://{domain}/.well-known/atproto-did`
  3. 解析成功 → Relay 更新 Handle 對應關係

### did:web 支援

組織或進階使用者可改用 `did:web`，自行 Host DID Document 於：
```
https://{domain}/.well-known/did.json
```

---

## 4. Phase 2 — Op Dispatch (Lexicon Record Signing)

```
App                           Relay (Elixir/Phoenix)
 |                                 |
 |  [create Lexicon record]        |
 |  {                              |
 |    "$type": "io.trisaura.post", |
 |    "text": "...",               |
 |    "createdAt": "ISO8601"       |
 |  }                              |
 |  [MST: insert record → CID]     |
 |  [sign Repo commit: Ed25519]    |
 |                                 |
 |-- POST /xrpc/com.atproto.repo.createRecord
 |   body: {                       |
 |     repo: "did:plc:...",        |
 |     collection: "io.trisaura.post",
 |     record: { ... },            |
 |     commit_sig: <hex ed25519>   |
 |   }                             |
 |                                 |
 |         [verify Ed25519 sig]    |
 |         [update MST index]      |
 |         [emit Firehose event]   |
 |         [broadcast to AppView]  |
 |<-- 200 OK { uri, cid } ---------|
```

### No Re-registration

Phase 2 只驗證 Ed25519 簽章與 DID cache 狀態，不重新執行 Passkeys 挑戰回應。

---

## 5. Lexicon Record Schema (io.trisaura.*)

```json
// io.trisaura.post
{
  "$type":     "io.trisaura.post",
  "text":      "string (max 3000 bytes UTF-8)",
  "replyTo":   "at://did:plc:.../io.trisaura.post/rkey (optional)",
  "threadId":  "uuid-v4 (optional)",
  "langs":     ["zh-TW", "en"],
  "createdAt": "2026-05-03T12:00:00.000Z"
}

// io.trisaura.reaction
{
  "$type":    "io.trisaura.reaction",
  "subject":  "at://did:plc:.../io.trisaura.post/rkey",
  "emoji":    "👍",
  "createdAt": "2026-05-03T12:00:00.001Z"
}
```

每筆記錄均由 DID 金鑰進行 CBOR 序列化後 Ed25519 簽章，寫入本地 MST。

---

## 6. MST Repo 結構

```
Repo (SQLite, local-first)
├── commits/          Signed MST commit objects (CID chain)
├── records/          Lexicon records keyed by (collection, rkey)
├── blobs/            Embedded media blobs (CID-addressed)
└── ops_queue/        Pending commits awaiting sync
    ├── status: pending | synced | rejected
    └── retry policy: reconnect → retry pending; rejected → log, no retry
```

MST (Merkle Search Tree) 確保：
- 同儕間增量同步只傳送差異節點
- 每個 Repo 版本可獨立雜湊驗證
- AppView 可從任一已知 commit 重建完整論壇快照

---

## 7. Firehose Relay (Comp C)

```
atproto Global Firehose ──WebSocket──► Elixir Relay
                                            │
                        Pattern Match on "$type" prefix
                                            │
                   ┌────────────────────────┴────────────────────────┐
                   │ io.trisaura.*          │ 其他 atproto records   │
                   │ → 過濾並轉發            │ → 忽略                 │
                   └────────────────────────┴────────────────────────┘
                                            │
                              GCP Pub/Sub → AppView (Comp D)
```

Firehose 訂閱端點（AT Protocol 標準）：
```
wss://{relay_host}/xrpc/com.atproto.sync.subscribeRepos
```

---

## 8. Transport

| Layer | Protocol | Notes |
|-------|----------|-------|
| App → Relay | HTTPS XRPC | `com.atproto.repo.createRecord` |
| Relay → AppView | GCP Pub/Sub | `io.trisaura.*` filtered events |
| Global Firehose | WebSocket | `com.atproto.sync.subscribeRepos` |
| Encryption in transit | TLS 1.3 | 標準 HTTPS/WSS |

---

## 9. Replay Protection

- 每筆 Repo commit 有唯一 CID（內容定址雜湊）
- Relay 以 CID 作去重依據，重複 commit 回傳 `409 Conflict`
- Phase 1 registration 包含 server-issued nonce，消費一次後失效

---

## 10. 離線優先（Offline-first Op Queue）

未能即時推送的 commit 存入本地 SQLite `ops_queue`：

| status | 行為 |
|--------|------|
| `pending` | 重連後自動重試 |
| `rejected` | 記錄錯誤，不重試 |
| `synced` | 7 天後可剪裁 |

---

## 11. Reputation Labeler（信任階層）

由 AppView 的 Labeler 服務維護，附加於 DID 記錄：

| 等級 | 條件 | 效果 |
|------|------|------|
| Basic | 僅有 Passkey | 一般發文權，受 Rate-Limit 管制 |
| DNS Verified | 擁有自訂 DNS Handle | 排序加權，較寬鬆的速率限制 |
| Verified Human | 外部中轉身分驗證（未來） | AppView 顯示 ✓ 標記，最寬鬆限制 |

### Anti-Spam

未認證 DID（Basic 等級）的發文受以下至少一項保護：
- **Rate Limiting**：每 DID 每分鐘最多 N 則記錄（可配置）
- **Proof of Work (PoW)**：Relay 可要求附上 Hashcash 式 PoW nonce

---

## 12. TODO Items

- [ ] 定義 did:plc genesis op 欄位格式（對齊 AT Protocol PLC spec）
- [ ] 定義 MST commit CBOR 序列化格式
- [ ] 完成 io.trisaura.* Lexicon 完整 JSON Schema
- [ ] 定義 Firehose 事件轉 Pub/Sub 的 envelope 格式
- [ ] 定義 Anti-Spam PoW 難度參數與調整策略
- [ ] 定義 Reputation Labeler 標籤欄位（對齊 com.atproto.label.defs）
- [ ] 定義加密 Op envelope（AES-256-GCM，私密社群用）
- [ ] 定義 Tombstone / 內容下架 Lexicon 類型

---

## 13. New Roadmap

| Phase | 里程碑 | 關鍵交付 |
|-------|--------|---------|
| P1 Alpha | Passkeys 登入 + did:plc 註冊 + 本地 MST Repo | 可發文的單節點 App |
| P2 Beta | Elixir Firehose Relay + AppView 基本閉環 | 發文 → Web 論壇可見 |
| P3 RC | DNS Handle 驗證 + AppView 索引優化 + Reputation Labeler | 公開上線前完整功能 |
| P4 Production | AI Agent Comp F — Firehose 資料摘要與過濾 | 智慧內容管理 |
