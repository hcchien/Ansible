/// Outbound sharing loop (PM review finding #2): construct the PUBLIC web URL
/// for a board/thread and parse inbound deep links back into the content they
/// point at.
///
/// The public URLs are served by the distribution frontend (SSR Open Graph
/// tags) at path-based routes:
///   /boards/:boardId
///   /boards/:boardId/threads/:threadId
///
/// The base origin is NOT a new config knob: it is derived from the forum
/// host's own public board URL (`HostedBoardProjection.canonicalBoardUri`,
/// e.g. `https://relay.example/boards/hosted-1`) — the same origin the relay
/// already advertises for public board views. Sharing therefore points at
/// exactly the origin the host publishes, with no invented environment value.
library;

/// Identifies a piece of public Elix content addressed by a link.
class ElixContentRef {
  /// 'board' or 'thread'.
  final String kind;
  final String boardId;

  /// Null for board links.
  final String? threadId;

  const ElixContentRef.board(this.boardId) : kind = 'board', threadId = null;

  const ElixContentRef.thread({required this.boardId, required String thread})
    : kind = 'thread',
      threadId = thread;

  bool get isThread => kind == 'thread';

  @override
  bool operator ==(Object other) =>
      other is ElixContentRef &&
      other.kind == kind &&
      other.boardId == boardId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(kind, boardId, threadId);

  @override
  String toString() =>
      'ElixContentRef($kind, board=$boardId, thread=$threadId)';
}

/// Builds public share URLs and parses inbound deep links.
class ElixContentLink {
  /// Custom-scheme host segment used for app deep links, kept distinct from the
  /// existing `trisaura://web-session` and `trisaura://mobilemoica` links.
  static const customScheme = 'trisaura';
  static const customContentHost = 'content';

  const ElixContentLink._();

  /// Returns the origin (`scheme://host[:port]`) of a forum host's public
  /// board URL, or null if it cannot be parsed.
  static String? originFromCanonicalBoardUri(String canonicalBoardUri) {
    final uri = Uri.tryParse(canonicalBoardUri);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port';
  }

  /// Public web URL for a board, derived from the host's canonical board URL.
  /// Returns null when no usable origin can be derived (caller then hides the
  /// share affordance rather than sharing a broken link).
  static String? boardUrl({
    required String canonicalBoardUri,
    required String boardId,
  }) {
    final origin = originFromCanonicalBoardUri(canonicalBoardUri);
    if (origin == null || boardId.isEmpty) return null;
    return '$origin/boards/${Uri.encodeComponent(boardId)}';
  }

  /// Public web URL for a thread within a board.
  static String? threadUrl({
    required String canonicalBoardUri,
    required String boardId,
    required String threadId,
  }) {
    final base = boardUrl(
      canonicalBoardUri: canonicalBoardUri,
      boardId: boardId,
    );
    if (base == null || threadId.isEmpty) return null;
    return '$base/threads/${Uri.encodeComponent(threadId)}';
  }

  /// Parses an inbound link into the content it references, or null when the
  /// link is not an Elix content link.
  ///
  /// Accepts two shapes:
  ///   - Custom scheme: `trisaura://content/boards/:id[/threads/:tid]`
  ///   - Web/universal: `https://host/boards/:id[/threads/:tid]`
  ///     (plain http permitted only for loopback hosts, mirroring the
  ///     web-session link policy, so a malicious LAN link cannot impersonate
  ///     a host).
  static ElixContentRef? parse(Uri uri, {bool allowLocalHttp = false}) {
    final segments = _contentSegments(uri, allowLocalHttp: allowLocalHttp);
    if (segments == null) return null;

    if (segments.length == 2 && segments[0] == 'boards') {
      final boardId = segments[1];
      if (boardId.isEmpty) return null;
      return ElixContentRef.board(boardId);
    }

    if (segments.length == 4 &&
        segments[0] == 'boards' &&
        segments[2] == 'threads') {
      final boardId = segments[1];
      final threadId = segments[3];
      if (boardId.isEmpty || threadId.isEmpty) return null;
      return ElixContentRef.thread(boardId: boardId, thread: threadId);
    }

    return null;
  }

  /// Extracts the `boards/...` path segments for a recognised content link, or
  /// null when the URI is not an Elix content link.
  static List<String>? _contentSegments(Uri uri, {required bool allowLocalHttp}) {
    if (uri.scheme == customScheme) {
      if (uri.host != customContentHost) return null;
      return uri.pathSegments.where((s) => s.isNotEmpty).toList();
    }

    if (uri.scheme == 'https' ||
        (uri.scheme == 'http' && allowLocalHttp && _isLoopbackHost(uri.host))) {
      if (uri.host.isEmpty) return null;
      return uri.pathSegments.where((s) => s.isNotEmpty).toList();
    }

    return null;
  }

  static bool _isLoopbackHost(String host) {
    final lower = host.toLowerCase();
    return lower == 'localhost' || lower == '::1' || lower.startsWith('127.');
  }
}
