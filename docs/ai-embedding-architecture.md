# 本地 Embedding 架構 — Murmur 語意搜尋

## 設計動機

用戶在 Ansible/Elix 中累積的 murmur 數量可達 1,000–5,000 筆。若每次搜尋都把所有 murmur 直接傳給 AI 做語意比對，將面臨以下問題：

- **Token 成本過高**：5,000 筆 murmur 每次搜尋可能消耗數十萬 token
- **回應速度慢**：大量文字送入 LLM 的 latency 無法接受
- **離線無法使用**：完全依賴 API，斷線即失效

**正確做法**：本地 embedding + vector search，AI 只負責最後的「合成」（synthesis）步驟。

---

## 整體架構概覽

```
┌─────────────────────────────────────────────────────────────┐
│                        Ansible App                          │
│                                                             │
│  ┌──────────────┐    ┌─────────────────────────────────┐   │
│  │ Write Path   │    │         Search Path              │   │
│  │              │    │                                  │   │
│  │ murmur saved │    │ query string                     │   │
│  │      ↓       │    │      ↓                           │   │
│  │ IndexingSvc  │    │ EmbeddingService.embed()         │   │
│  │      ↓       │    │      ↓                           │   │
│  │ EmbeddingSvc │    │ VectorSearchService              │   │
│  │      ↓       │    │  cosine similarity (純 Dart)     │   │
│  │ Repository   │    │      ↓                           │   │
│  │      ↓       │    │ List<MurmurSearchResult>         │   │
│  │   SQLite     │    │      ↓                           │   │
│  │   (drift)    │    │ C·06 勾選清單                    │   │
│  └──────────────┘    └─────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  Synthesis Path                      │   │
│  │  (唯一的 AI API call)                                │   │
│  │                                                      │   │
│  │  selectedMurmurs + note.body                        │   │
│  │       ↓                                              │   │
│  │  OpenAiCompatibleProvider.complete()                │   │
│  │       ↓                                              │   │
│  │  draft paragraph → append to note                   │   │
│  │       ↓                                              │   │
│  │  ContentRelation.create(murmurId → noteId)          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 三條核心路徑

### 1. Write Path（murmur 存入時）

每次 murmur 寫入後，同步觸發 indexing：

```
ContentItem saved
    ↓
MurmurIndexingService.index(murmur)
    ↓
EmbeddingService.embed(body)          ← Apple NL MethodChannel
    ↓
MurmurEmbeddingRepository.upsert(id, vector)
    ↓
murmur_embeddings 表（SQLite / drift）
```

### 2. Search Path（AgentSheet 搜尋，零 API 成本）

```
query string
    ↓
EmbeddingService.embed(query)         ← Apple NL，~5ms
    ↓
VectorSearchService.findNearest(queryVec, k=20)
    ↓
純 Dart cosine similarity
5,000 筆 < 15ms
    ↓
List<MurmurSearchResult>
    ↓
C·06 勾選清單（ResultSheet）
```

### 3. Synthesis Path（唯一的 AI API call）

```
selectedMurmurs（用戶勾選）+ note.body
    ↓
OpenAiCompatibleProvider.complete(synthesisRequest)
    ↓
draft paragraph
    ↓
append to note
    ↓
ContentRelation.create(murmurId → noteId, "compiled_into")
```

---

## 新增檔案結構

```
ansible_core/store/lib/src/
  schema/
    murmur_embeddings.dart              ← drift Table 定義
  repositories/
    murmur_embedding_repository.dart    ← upsert / getAll / delete

ansible_node/app/lib/services/ai/
  embedding_service.dart               ← abstract interface
  apple_nl_embedding_service.dart      ← iOS MethodChannel impl
  vector_search_service.dart           ← cosine similarity，純 Dart
  murmur_indexing_service.dart         ← write path + 補齊舊資料
```

iOS 原生端（Swift）：

```
ios/Runner/
  AppDelegate.swift                    ← registerEmbeddingChannel()
  EmbeddingChannel.swift               ← NLEmbedding wrapper
```

---

## DB Schema — MurmurEmbeddings

### Drift Table 定義

```dart
class MurmurEmbeddings extends Table {
  TextColumn get contentItemId =>
      text().references(ContentItems, #contentItemId)();
  TextColumn get modelVersion => text()();   // e.g. 'apple-nl-tc-v1'
  TextColumn get vectorBlob => text()();     // base64(float32[])
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {contentItemId};
}
```

### 為什麼用 base64 而不是 JSON float array？

| 格式 | 512 維 float32 的大小 |
|------|----------------------|
| Raw binary | 2 KB |
| **base64** | **~2.7 KB** |
| JSON float array | ~7 KB |

base64 讀寫快、空間節省約 60%，且可直接存入 SQLite TEXT column，無需額外序列化邏輯。

### Migration

schemaVersion: `16 → 17`，新增 `murmur_embeddings` 表。

---

## EmbeddingService 介面

```dart
abstract class EmbeddingService {
  /// 將文字轉換為向量（embedding）
  Future<List<double>> embed(String text);

  /// 向量維度（Apple NL: 512 / MiniLM: 384）
  int get dimension;

  /// model 識別字，用來判斷是否需要 re-index
  String get modelVersion;
}
```

---

## iOS 實作 — Apple NaturalLanguage

### MethodChannel 名稱

```
ansible_node/embedding
```

### Swift 實作概要

```swift
// EmbeddingChannel.swift
import NaturalLanguage

func getEmbedding(text: String) -> [Double]? {
  guard let embedding = NLEmbedding.sentenceEmbedding(for: .traditionalChinese)
  else { return nil }
  return embedding.vector(for: text)
}
```

### 規格

| 項目 | 規格 |
|------|------|
| API | `NLEmbedding.sentenceEmbedding(for: .traditionalChinese)` |
| 最低 iOS 版本 | **14.0**（原 deployment target 13.0 需調整） |
| 向量維度 | 512 |
| 推理速度 | ~5ms / 筆 |
| 網路需求 | 無（完全本地） |

### AppDelegate 修改

```swift
// AppDelegate.swift
override func application(...) -> Bool {
  GeneratedPluginRegistrant.register(with: self)
  registerEmbeddingChannel()   // ← 新增
  return super.application(...)
}
```

---

## VectorSearchService

### Cosine Similarity（純 Dart，零依賴）

```dart
// cosine similarity，純 Dart，零依賴
static double cosine(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (var i = 0; i < a.length; i++) {
    dot   += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB));
}
```

### findNearest

```dart
Future<List<MurmurSearchResult>> findNearest(
  List<double> queryVec, {
  int k = 20,
  DateTime? since,   // null = 全部；非 null = 時間篩選
}) async { ... }
```

### Filter Chips 對應

| Chip 標籤 | 參數 |
|-----------|------|
| 最近兩週 | `since: DateTime.now().subtract(Duration(days: 14))` |
| 全部 | `since: null` |

### 效能基準

| 筆數 | 時間（純 Dart cosine） |
|------|----------------------|
| 1,000 筆 | < 3ms |
| 5,000 筆 | < 15ms |

---

## MurmurIndexingService

### 兩個觸發時機

```
時機 1：即時（Write Path）
  ContentItemRepository.create() / update()
      ↓
  MurmurIndexingService.index(murmur)

時機 2：補齊（App 啟動）
  App.onReady()
      ↓
  MurmurIndexingService.indexAllPending()
      ↓
  background isolate（避免 UI jank）
  1,000 筆 ≈ 5 秒
```

### Re-index 觸發條件

```dart
// model version 變更時，需全量 re-index
if (storedModelVersion != embeddingService.modelVersion) {
  await indexAll(); // 清除舊 embeddings，重新計算
}
```

---

## AI Synthesis Request Schema

發送給 `OpenAiCompatibleProvider` 的請求結構：

```json
{
  "task": "synthesize_for_note",
  "note_context": {
    "title": "...",
    "body_excerpt": "..."
  },
  "selected_murmurs": [
    { "body": "..." },
    { "body": "..." }
  ],
  "output_schema": {
    "draft_paragraph": "string"
  }
}
```

AI 回傳 `draft_paragraph`，直接 append 至 note body。

---

## ContentRelation

murmur 編入 note 後，建立雙向關係記錄：

```dart
ContentRelation.create(
  fromContentItemId: murmur.id,
  toContentItemId: note.id,
  relationType: 'compiled_into',
);
```

### 用途

- 「由 N 個 murmur 編成」的數字來源
- 未來可從 note 反查哪些 murmur 被編入
- 避免重複編入同一 murmur

---

## 實作順序

### Week 1 — 地基

```
1. MurmurEmbeddings table + DB migration (schemaVersion 16 → 17)
2. MurmurEmbeddingRepository（upsert / getAll / deleteByModelVersion）
3. EmbeddingService 介面 + AppleNLEmbeddingService
4. iOS deployment target 調整至 14.0
5. AppDelegate 加 registerEmbeddingChannel()
```

### Week 2 — 搜尋核心

```
6. VectorSearchService（cosine similarity + findNearest）
7. MurmurIndexingService
   - index()：write path
   - indexAllPending()：補齊舊資料，background isolate
8. 接進 ContentItemRepository 的 create / update
```

### Week 3 — UI + AI Synthesis

```
9.  AgentSheet (C·05)：搜尋輸入 + filter chips
10. ResultSheet (C·06)：搜尋結果 + 勾選清單
11. AI synthesis API call（OpenAiCompatibleProvider）
12. 編入 note + ContentRelation.create()
```

---

## 抽換策略

`EmbeddingService` 是 abstract interface，未來切換底層實作時，**上層程式碼完全不動**：

```
EmbeddingService (abstract)
    ├── AppleNLEmbeddingService   ← 現在用這個
    └── OnnxEmbeddingService      ← 未來可切換
```

### 實作比較

| 實作 | 維度 | Bundle 大小 | 品質 | 平台 |
|------|------|-------------|------|------|
| `AppleNLEmbeddingService` | 512 | 0 MB（OS 內建） | 中等 | iOS 14+ |
| `OnnxEmbeddingService` | 384 | ~85 MB | 優秀 | 跨平台（iOS / Android / macOS） |

ONNX 方案採用 `paraphrase-multilingual-MiniLM-L12-v2`，多語言品質更佳，但需打包模型檔至 app bundle。切換時只需：

1. 新增 `OnnxEmbeddingService` 實作
2. 在 DI container 替換注入的實作
3. 觸發全量 re-index（modelVersion 不同會自動偵測）

---

## 資料流總結

```
┌──────────┐   embed()    ┌─────────────────┐   upsert()   ┌──────────────────┐
│  murmur  │ ──────────→  │ EmbeddingService │ ──────────→  │ murmur_embeddings│
│  body    │              │ (Apple NL / ONNX)│              │   (SQLite)       │
└──────────┘              └─────────────────┘              └──────────────────┘
                                                                    ↓
                                                            VectorSearchService
                                                            cosine similarity
                                                                    ↓
┌──────────┐   embed()    ┌─────────────────┐              ┌──────────────────┐
│  query   │ ──────────→  │ EmbeddingService │ ──────────→  │ Top-K results    │
│  string  │              └─────────────────┘              │ (MurmurSearch    │
└──────────┘                                               │  Result list)    │
                                                            └──────────────────┘
                                                                    ↓
                                                            User 勾選
                                                                    ↓
                                                            AI Synthesis
                                                            (一次 API call)
                                                                    ↓
                                                            draft paragraph
                                                            → append to note
```
