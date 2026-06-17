/// Lexicon record types for the io.trisaura.* namespace (V2.0).
///
/// These model the AT Protocol Lexicon records published and consumed
/// by the Tris-Aura PDS / relay.

/// A post record — the primary content unit.
class LexiconPost {
  static const String type = 'io.trisaura.post';

  final String text;
  final String createdAt;
  final String? replyTo;
  final String? threadId;
  final String? boardId;

  const LexiconPost({
    required this.text,
    required this.createdAt,
    this.replyTo,
    this.threadId,
    this.boardId,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'text': text,
    'createdAt': createdAt,
    if (replyTo != null) 'replyTo': replyTo,
    if (threadId != null) 'threadId': threadId,
    if (boardId != null) 'boardId': boardId,
  };
}

/// Short-form thought capture record.
class LexiconMurmur {
  static const String type = 'io.trisaura.murmur';

  final String text;
  final String createdAt;
  final String? tone;
  final String? sourceType;
  final List<String>? langs;

  const LexiconMurmur({
    required this.text,
    required this.createdAt,
    this.tone,
    this.sourceType,
    this.langs,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'text': text,
    if (tone != null) 'tone': tone,
    if (sourceType != null) 'sourceType': sourceType,
    if (langs != null) 'langs': langs,
    'createdAt': createdAt,
  };
}

/// Authored structured writing record.
class LexiconNote {
  static const String type = 'io.trisaura.note';

  final String body;
  final String visibility;
  final String createdAt;
  final String? updatedAt;
  final String? title;
  final String? thesis;
  final String? summary;
  final List<Map<String, String>>? outline;
  final List<String>? langs;

  const LexiconNote({
    required this.body,
    required this.visibility,
    required this.createdAt,
    this.updatedAt,
    this.title,
    this.thesis,
    this.summary,
    this.outline,
    this.langs,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    if (title != null) 'title': title,
    'body': body,
    if (thesis != null) 'thesis': thesis,
    if (summary != null) 'summary': summary,
    if (outline != null) 'outline': outline,
    'visibility': visibility,
    if (langs != null) 'langs': langs,
    'createdAt': createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
  };
}

/// Public discussion root record.
class LexiconDiscussion {
  static const String type = 'io.trisaura.discussion';

  final String title;
  final String body;
  final String discussionShape;
  final String participationPolicy;
  final String forkPolicy;
  final String consensusState;
  final String createdAt;
  final String updatedAt;
  final String? boardId;
  final String? threadId;

  const LexiconDiscussion({
    required this.title,
    required this.body,
    required this.discussionShape,
    required this.participationPolicy,
    required this.forkPolicy,
    required this.consensusState,
    required this.createdAt,
    required this.updatedAt,
    this.boardId,
    this.threadId,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'title': title,
    'body': body,
    'discussionShape': discussionShape,
    'participationPolicy': participationPolicy,
    'forkPolicy': forkPolicy,
    'consensusState': consensusState,
    if (boardId != null) 'boardId': boardId,
    if (threadId != null) 'threadId': threadId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

/// Public lineage edge between content records.
class LexiconContentRelation {
  static const String type = 'io.trisaura.contentRelation';

  final String from;
  final String to;
  final String relationType;
  final String createdAt;

  const LexiconContentRelation({
    required this.from,
    required this.to,
    required this.relationType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'from': from,
    'to': to,
    'relationType': relationType,
    'createdAt': createdAt,
  };
}

/// Reviewable transformation metadata record.
class LexiconTransformation {
  static const String type = 'io.trisaura.transformation';

  final List<String> sourceRefs;
  final String targetRef;
  final String targetMode;
  final String providerType;
  final String status;
  final String createdAt;
  final String? completedAt;
  final String? promptProfile;

  const LexiconTransformation({
    required this.sourceRefs,
    required this.targetRef,
    required this.targetMode,
    required this.providerType,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.promptProfile,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'sourceRefs': sourceRefs,
    'targetRef': targetRef,
    'targetMode': targetMode,
    'providerType': providerType,
    if (promptProfile != null) 'promptProfile': promptProfile,
    'status': status,
    'createdAt': createdAt,
    if (completedAt != null) 'completedAt': completedAt,
  };
}

/// Acknowledged transition from authored note to public discussion.
class LexiconProjection {
  static const String type = 'io.trisaura.projection';

  final String source;
  final String target;
  final String projectedExcerpt;
  final String participationPolicy;
  final bool ownershipTransferAcknowledged;
  final String createdAt;

  const LexiconProjection({
    required this.source,
    required this.target,
    required this.projectedExcerpt,
    required this.participationPolicy,
    required this.ownershipTransferAcknowledged,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'source': source,
    'target': target,
    'projectedExcerpt': projectedExcerpt,
    'participationPolicy': participationPolicy,
    'ownershipTransferAcknowledged': ownershipTransferAcknowledged,
    'createdAt': createdAt,
  };
}

/// A reaction to a record (emoji response).
class LexiconReaction {
  static const String type = 'io.trisaura.reaction';

  /// AT-URI of the record being reacted to
  final String subject;
  final String emoji;
  final String createdAt;

  const LexiconReaction({
    required this.subject,
    required this.emoji,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'subject': subject,
    'emoji': emoji,
    'createdAt': createdAt,
  };
}

/// A tombstone record indicating a soft-deleted record.
class LexiconTombstone {
  static const String type = 'io.trisaura.tombstone';

  /// AT-URI of the record being deleted
  final String subject;
  final String createdAt;

  const LexiconTombstone({required this.subject, required this.createdAt});

  Map<String, dynamic> toJson() => {
    r'$type': type,
    'subject': subject,
    'createdAt': createdAt,
  };
}

/// A Lexicon record after signing — ready for AT Protocol repo commit.
class SignedLexiconRecord {
  /// The original record as a JSON map (includes \$type)
  final Map<String, dynamic> record;

  /// DAG-CBOR CID of the record, base32-encoded (CIDv1 / raw codec)
  final String cid;

  /// Ed25519 signature over the DAG-CBOR bytes, hex-encoded (64 bytes)
  final String commitSigHex;

  /// The author's DID
  final String authorDid;

  const SignedLexiconRecord({
    required this.record,
    required this.cid,
    required this.commitSigHex,
    required this.authorDid,
  });
}
