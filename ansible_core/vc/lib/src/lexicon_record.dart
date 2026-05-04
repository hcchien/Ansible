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

  const LexiconPost({
    required this.text,
    required this.createdAt,
    this.replyTo,
    this.threadId,
  });

  Map<String, dynamic> toJson() => {
        r'$type': type,
        'text': text,
        'createdAt': createdAt,
        if (replyTo != null) 'replyTo': replyTo,
        if (threadId != null) 'threadId': threadId,
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

  const LexiconTombstone({
    required this.subject,
    required this.createdAt,
  });

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
