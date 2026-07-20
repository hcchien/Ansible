enum LocalSearchKind { board, thread, post, note, murmur }

enum LocalSearchScope { all, private, circle, public }

class LocalSearchResult {
  const LocalSearchResult({
    required this.kind,
    required this.entityId,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.boardId,
    this.threadId,
    this.authorDid,
    this.visibility,
    this.localOnly = false,
  });

  final LocalSearchKind kind;
  final String entityId;
  final String title;
  final String body;
  final DateTime updatedAt;
  final String? boardId;
  final String? threadId;
  final String? authorDid;
  final String? visibility;
  final bool localOnly;
}
