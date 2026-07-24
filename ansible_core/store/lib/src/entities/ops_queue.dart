/// A pending CRDT operation waiting to be forwarded to the Relay.
///
/// V1.1 Comp B: P2P Sync Engine — Operation Log
/// Mirrors the rusqlite Ops queue described in the spec, but kept here
/// as the Dart-side model until the Rust FFI bridge is in place.
///
/// Lifecycle:
///   created → [pending] → signed (Ed25519) → [sent] → ack from relay → [synced]
///   Network failures stay [pending]. Recoverable policy/capability failures
///   become [blocked] until an explicit sync retry; malformed ops are
///   [rejected].
///
/// Fields:
/// - [opId]       — UUID v4 generated locally
/// - [authorDid]  — DID of the local identity that produced this Op
/// - [entityType] — "board" | "thread" | "post" | "reaction"
/// - [entityId]   — target entity UUID
/// - [opType]     — CRDT operation type: "insert" | "update" | "delete" | "crdt_merge"
/// - [payload]    — JSON-encoded CRDT delta (Yrs binary encoded as base64)
/// - [signature]  — Ed25519 signature over (opId + payload), hex-encoded
/// - [schemaVersion] — op payload format version (Phase 0 — API versioning);
///   1 is the only format that exists today, so it doubles as the default
/// - [status]     — "pending" | "blocked" | "sent" | "synced" | "rejected"
/// - [createdAt]  — local wall-clock time
/// - [sentAt]     — null until first transmission attempt
class OpsQueueEntry {
  final String opId;
  final String authorDid;
  final String entityType;
  final String entityId;
  final String opType;
  final String payload; // base64-encoded Yrs binary delta
  final String signature; // Ed25519 over opId+payload, hex-encoded
  final int schemaVersion; // op payload format version (currently always 1)
  final String status; // pending | blocked | sent | synced | rejected
  final DateTime createdAt;
  final DateTime? sentAt;

  const OpsQueueEntry({
    required this.opId,
    required this.authorDid,
    required this.entityType,
    required this.entityId,
    required this.opType,
    required this.payload,
    required this.signature,
    this.schemaVersion = 1,
    this.status = 'pending',
    required this.createdAt,
    this.sentAt,
  });

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'authorDid': authorDid,
    'entityType': entityType,
    'entityId': entityId,
    'opType': opType,
    'payload': payload,
    'signature': signature,
    'schemaVersion': schemaVersion,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'sentAt': sentAt?.toIso8601String(),
  };

  factory OpsQueueEntry.fromJson(Map<String, dynamic> json) => OpsQueueEntry(
    opId: json['opId'] as String,
    authorDid: json['authorDid'] as String,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    opType: json['opType'] as String,
    payload: json['payload'] as String,
    signature: json['signature'] as String,
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
    status: json['status'] as String? ?? 'pending',
    createdAt: DateTime.parse(json['createdAt'] as String),
    sentAt: json['sentAt'] != null
        ? DateTime.parse(json['sentAt'] as String)
        : null,
  );

  OpsQueueEntry copyWith({
    String? opId,
    String? authorDid,
    String? entityType,
    String? entityId,
    String? opType,
    String? payload,
    String? signature,
    int? schemaVersion,
    String? status,
    DateTime? createdAt,
    DateTime? sentAt,
  }) {
    return OpsQueueEntry(
      opId: opId ?? this.opId,
      authorDid: authorDid ?? this.authorDid,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      opType: opType ?? this.opType,
      payload: payload ?? this.payload,
      signature: signature ?? this.signature,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
    );
  }
}
