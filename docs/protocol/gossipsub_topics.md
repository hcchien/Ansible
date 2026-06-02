# AT Protocol Lexicon & Firehose Topic Conventions

> Status: Active compatibility/target spec; implementation is partial
> Supersedes: Gossipsub `/ansible/ops/v1` topic naming (V1.x)  
> Scope: Tris-Aura Lexicon namespace, Firehose filter, XRPC routing

---

Transition note: this document describes the current AT Protocol-shaped
compatibility surface and remains valid for XRPC/Firehose tests. It does not
define the required public federation identity. New federation work treats
AT-URI / `did:plc` records as optional compatibility or discovery context;
Nostr uses `did:nostr` public keys, and ActivityPub uses relay-domain Actor
URLs.

Current implementation status: the relay currently exposes XRPC
`com.atproto.repo.createRecord` and `com.atproto.identity.resolveHandle` as a
compatibility slice. It does not expose `subscribeRepos`, `deleteRecord`, or
`getRepo`, does not subscribe to the global atproto Firehose, and does not
forward filtered events to GCP Pub/Sub/AppView.

---

## 1. Lexicon Namespace

所有 Tris-Aura 自訂記錄類型使用保留的反向網域命名空間：

```text
io.trisaura.{record-type}
```

範例：

```text
io.trisaura.post
io.trisaura.reaction
io.trisaura.thread
io.trisaura.tombstone
io.trisaura.label
```

`record-type` 必須符合：

```text
^[a-z][a-z0-9]*$
```

---

## 2. 已定義的 Lexicon 類型

| Lexicon NSID | 用途 |
|---|---|
| `io.trisaura.post` | 論壇貼文或回覆 |
| `io.trisaura.reaction` | 貼文表情回應（emoji） |
| `io.trisaura.thread` | 討論串元資料 |
| `io.trisaura.tombstone` | 軟刪除 / 模組下架標記（append-only） |
| `io.trisaura.label` | Reputation Labeler 簽章標籤 |

---

## 3. AT-URI 路徑格式

每筆記錄的唯一識別符遵循 AT Protocol URI 格式：

```text
at://{did}/{collection}/{rkey}
```

範例：

```text
at://did:plc:abc123/io.trisaura.post/3jxtb6fvzca2s
at://did:web:example.com/io.trisaura.reaction/3jxtbz7abc00
```

`rkey` 必須為 TID（Timestamp ID）或 UUID，確保單調遞增排序。

---

## 4. Firehose 訂閱與過濾

### 訂閱端點（Target）

```text
wss://{relay_host}/xrpc/com.atproto.sync.subscribeRepos
```

Target Relay behavior subscribes to the global atproto Firehose through this
endpoint. This is not implemented in the current Phoenix MVP.

### 過濾規則

Target Elixir Relay behavior uses pattern matching to filter events:

```
事件 $type 前綴 = "io.trisaura." → 保留，轉發至 AppView (GCP Pub/Sub)
其他 $type                       → 忽略，不記錄內容
```

Target filtered events use this GCP Pub/Sub topic naming:

```text
trisaura-ops-{network}
```

| network | Pub/Sub Topic |
|---------|---------------|
| mainnet | `trisaura-ops-mainnet` |
| testnet | `trisaura-ops-testnet` |
| devnet  | `trisaura-ops-devnet` |

### 驗證順序

1. 確認 Repo DID 在 Active DID cache 中
2. 解碼 CBOR Lexicon record
3. 驗證 Ed25519 `commit_sig`
4. 檢查 CID 是否已存在（去重）
5. 轉發至 Pub/Sub

---

## 5. XRPC 路由

App → Relay 的直接發文路徑：

| XRPC Method | Current status |
|---|---|
| `com.atproto.repo.createRecord` | Implemented compatibility path; validates signed record and appends to OpStore with stub CID |
| `com.atproto.repo.deleteRecord` | Target only; not routed in current Phoenix MVP |
| `com.atproto.sync.getRepo` | Target only; not routed in current Phoenix MVP |
| `com.atproto.identity.resolveHandle` | Implemented compatibility path |

---

## 6. 版本管理規則

- Lexicon NSID 中的 `io.trisaura.` 前綴為 V2.0 的主要命名空間。
- Breaking changes 需建立新的 record type（例如 `io.trisaura.post.v2`）。
- 可向後兼容的欄位新增維持在相同 NSID 下，舊客戶端安全忽略。

---

## 7. Enforcement

違反 Lexicon 規範或簽章驗證失敗的記錄將被 Relay 拒絕，並回傳對應錯誤碼：

| 錯誤碼 | 含義 |
|---|---|
| `InvalidLexicon` | `$type` 不在 `io.trisaura.*` 命名空間內 |
| `InvalidSignature` | Ed25519 簽章驗證失敗 |
| `DuplicateCid` | Target Firehose/AppView behavior; current XRPC path returns a stub CID |
| `UnknownDid` | DID 未在 Active cache 中 |
| `RateLimitExceeded` | DID 發文頻率超過 Token Bucket 限制 |

---

## 附錄 A: V1.x Gossipsub Topics（已棄用）

V1.x 使用的 `/ansible/ops/v1/{network}/{scope}` libp2p Gossipsub 主題格式
已於 V2.0 中廢棄，改為 AT Protocol Firehose + XRPC 架構。

舊格式保留於 [`tris_aura_sync_spec_v1.1.md`](./tris_aura_sync_spec_v1.1.md)
（已標記 Superseded）作為歷史參考，不再於新節點中使用。
