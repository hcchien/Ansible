class PostMention {
  final String did;
  final String token;

  const PostMention({required this.did, required this.token});

  Map<String, dynamic> toJson() => {'did': did, 'token': token};

  factory PostMention.fromJson(Map<String, dynamic> json) => PostMention(
    did: json['did'] as String? ?? '',
    token: json['token'] as String? ?? '',
  );
}

class Post {
  final String id;
  final String threadId;
  final String boardId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastEditAt;
  final String? parentPostId;
  final bool isDeleted;

  /// True when this post's authoring op carried a valid Ed25519 signature
  /// (signed locally on create, or verified on sync).
  final bool signatureVerified;
  final List<PostMention> mentions;

  Post({
    required this.id,
    required this.threadId,
    required this.boardId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.lastEditAt,
    this.parentPostId,
    this.isDeleted = false,
    this.signatureVerified = false,
    this.mentions = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'threadId': threadId,
      'boardId': boardId,
      'authorId': authorId,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastEditAt': lastEditAt.toIso8601String(),
      'parentPostId': parentPostId,
      'isDeleted': isDeleted,
      'signatureVerified': signatureVerified,
      'mentions': mentions.map((mention) => mention.toJson()).toList(),
    };
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    final authorId =
        json['authorId'] as String? ?? json['authorDid'] as String?;
    if (authorId == null || authorId.isEmpty) {
      throw ArgumentError('Post authorId is required');
    }

    final boardId = json['boardId'] as String? ?? json['board_id'] as String?;
    if (boardId == null || boardId.isEmpty) {
      throw ArgumentError('Post boardId is required');
    }

    return Post(
      id: json['id'] as String,
      threadId: json['threadId'] as String,
      boardId: boardId,
      authorId: authorId,
      content: json['content'] as String,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['createdAt']),
      lastEditAt: _parseDate(
        json['lastEditAt'] ?? json['updatedAt'] ?? json['createdAt'],
      ),
      parentPostId: json['parentPostId'] as String?,
      isDeleted: json['isDeleted'] as bool? ?? false,
      signatureVerified: json['signatureVerified'] as bool? ?? false,
      mentions: (json['mentions'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => PostMention.fromJson(Map<String, dynamic>.from(value)),
          )
          .where(
            (mention) =>
                mention.did.startsWith('did:') && mention.token.isNotEmpty,
          )
          .take(10)
          .toList(growable: false),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value == null) {
      return DateTime.now().toUtc();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.parse(value);
    }
    throw ArgumentError('Invalid date value "$value"');
  }
}
