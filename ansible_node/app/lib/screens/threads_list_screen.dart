import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../l10n/moderation_copy.dart';
import '../services/app_view_timeline_client.dart';
import '../services/elix_content_link.dart';
import '../services/external_content_preferences_controller.dart';
import '../services/posting_gate.dart';
import '../widgets/external_content_section.dart';
import '../widgets/posting_gate_notice.dart';
import '../widgets/thread_form_dialog.dart';
import 'posts_view_screen.dart';

/// Fetches a board's curated external items. Mirrors the AppView client method
/// signature so tests can inject a fake without a real HTTP client.
typedef BoardExternalFetcher =
    Future<AppViewExternalPage> Function(String boardId);

Future<void> _defaultBoardShareSheet(String text, {String? subject}) {
  return Share.share(text, subject: subject);
}

class ThreadsListScreen extends StatefulWidget {
  final AppDatabase db;
  final Board board;

  /// The local user's DID; used to check this board's posting gate. When
  /// null, the gate check falls back to the unverified default tier.
  final String? localDid;

  /// Platform share-sheet seam (overridable in tests).
  final ShareSheet shareSheet;

  /// Per-user opt-in for external (fediverse) content. When null the screen
  /// builds its own controller from SharedPreferences (default OFF). One of the
  /// two gates for surfacing external content (inbound-federation D4).
  final ExternalContentPreferencesController? externalContentPreferences;

  /// Test/override seam for fetching the board's external items. When null the
  /// screen uses the AppView client (only when the AppView base URL is set).
  final BoardExternalFetcher? externalFetcher;

  const ThreadsListScreen({
    super.key,
    required this.db,
    required this.board,
    this.localDid,
    this.shareSheet = _defaultBoardShareSheet,
    this.externalContentPreferences,
    this.externalFetcher,
  });

  @override
  State<ThreadsListScreen> createState() => _ThreadsListScreenState();
}

class _ThreadsListScreenState extends State<ThreadsListScreen> {
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;
  List<Thread> _threads = [];
  bool _isLoading = true;

  /// Host moderation overlay: lock entries keyed by thread id (reason-coded).
  Map<String, HostModerationState> _lockedByThreadId = const {};

  /// Set when this board is hosted by a Forum Host; only hosted boards have a
  /// public web URL to share.
  HostedBoardProjection? _hostedProjection;

  /// True when the board requires a higher tier than the local user has.
  /// Client-side UX only — the relay re-checks at intent acceptance.
  bool _postingBlocked = false;

  /// Curated external (fediverse) items for this board, fetched ONLY when both
  /// gates pass (board.externalInclusion AND the user opt-in). Empty otherwise.
  List<AppViewExternalItem> _externalItems = const [];

  late final ExternalContentPreferencesController _externalPrefs;

  @override
  void initState() {
    super.initState();
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _externalPrefs =
        widget.externalContentPreferences ??
        ExternalContentPreferencesController();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() => _isLoading = true);
    final threads = await _threadRepo.list(boardId: widget.board.id);
    final projection = await DriftHostedBoardRepository(
      widget.db,
    ).getProjectionByLocalBoardId(widget.board.id);
    final postingBlocked = await _checkPostingGate(projection);
    final moderationEntries = await DriftHostModerationStateRepository(
      widget.db,
    ).listForBoard(widget.board.id);
    final lockedByThreadId = {
      for (final entry in moderationEntries)
        if (entry.targetKind == HostModerationState.targetKindThread &&
            entry.action == HostModerationState.actionLocked)
          entry.targetRef: entry,
    };
    final externalItems = await _loadExternalItems(projection);
    setState(() {
      _threads = threads;
      _hostedProjection = projection;
      _postingBlocked = postingBlocked;
      _lockedByThreadId = lockedByThreadId;
      _externalItems = externalItems;
      _isLoading = false;
    });
  }

  /// Fetches the board's curated external items ONLY when BOTH gates pass:
  /// the board is external-inclusive AND the user opted into external content
  /// (inbound-federation Constitution must-have). Returns an empty list — and
  /// makes NO network call — when either gate is closed.
  Future<List<AppViewExternalItem>> _loadExternalItems(
    HostedBoardProjection? projection,
  ) async {
    if (projection == null || !projection.externalInclusion) return const [];
    final allowed = await _externalPrefs.externalAllowed();
    if (!allowed) return const [];

    final fetcher = _resolveExternalFetcher();
    if (fetcher == null) return const [];
    try {
      final page = await fetcher(projection.hostedBoardId);
      return page.items;
    } catch (_) {
      // External content is best-effort and non-load-bearing: a fetch failure
      // never blocks the native thread list.
      return const [];
    }
  }

  BoardExternalFetcher? _resolveExternalFetcher() {
    if (widget.externalFetcher != null) return widget.externalFetcher;
    if (AppEnvironment.appViewBaseUrl.isEmpty) return null;
    final client = AppViewTimelineClient(
      baseUrl: AppEnvironment.appViewBaseUrl,
    );
    return (boardId) => client.fetchBoardExternal(boardId);
  }

  Future<bool> _checkPostingGate(HostedBoardProjection? projection) async {
    final requiredTier = projection?.minPostTier;
    if (requiredTier == null) return false;
    final did = widget.localDid;
    final tier = did == null
        ? PostingGate.basicTier
        : await DriftDidReputationRepository(widget.db).tierFor(did);
    return !PostingGate.satisfies(tier, requiredTier);
  }

  /// Public web URL for this board on the distribution frontend, or null when
  /// the board is local-only (no hosted projection ⇒ nothing public to share).
  String? get _boardShareUrl {
    final projection = _hostedProjection;
    if (projection == null) return null;
    return ElixContentLink.boardUrl(
      canonicalBoardUri: projection.canonicalBoardUri,
      boardId: projection.hostedBoardId,
    );
  }

  /// Opens the platform share sheet with this board's public web URL.
  Future<void> _shareBoard() async {
    final url = _boardShareUrl;
    if (url == null) return;
    await widget.shareSheet(url, subject: widget.board.title);
  }

  Future<void> _createThread() async {
    final dialogResult = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => ThreadFormDialog(
        boards: [widget.board],
        initialBoardId: widget.board.id,
      ),
    );

    if (dialogResult != null) {
      final title = dialogResult['title']?.trim();
      final boardId = dialogResult['boardId'];
      final content = dialogResult['content']?.trim() ?? '';
      if (title == null ||
          title.isEmpty ||
          boardId == null ||
          boardId.isEmpty) {
        return;
      }
      final now = DateTime.now();
      final thread = Thread(
        id: const Uuid().v4(),
        boardId: boardId,
        title: title,
        authorId: 'user-local', // Placeholder for now
        createdAt: now,
        updatedAt: now,
      );
      await _threadRepo.create(thread);
      if (content.isNotEmpty) {
        await _postRepo.create(
          Post(
            id: const Uuid().v4(),
            threadId: thread.id,
            boardId: boardId,
            authorId: 'user-local', // Placeholder for now
            content: content,
            createdAt: now,
            updatedAt: now,
            lastEditAt: now,
            parentPostId: null,
          ),
        );
      }
      await _loadThreads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.board.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_boardShareUrl != null)
            IconButton(
              key: const Key('share_board_button'),
              icon: const Icon(Icons.ios_share, size: 21),
              tooltip: context.uiCopy(zh: '分享看板', en: 'Share board'),
              onPressed: _shareBoard,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_postingBlocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: PostingGateNotice(
                      localDid: widget.localDid ?? '',
                      onUpgradeCompleted: _loadThreads,
                    ),
                  ),
                Expanded(
                  child: _externalItems.isEmpty
                      ? _threadsBody(context)
                      : ListView(
                          children: [
                            for (final thread in _threads)
                              _threadCard(context, thread),
                            ExternalContentSection(items: _externalItems),
                          ],
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _postingBlocked ? null : _createThread,
        tooltip: _postingBlocked
            ? context.uiCopy(
                zh: '需通過真人驗證才能發文',
                en: 'Verified humans only',
              )
            : context.uiCopy(zh: '建立討論串', en: 'Create thread'),
        backgroundColor: _postingBlocked ? Colors.grey[400] : null,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _threadsBody(BuildContext context) {
    return _threads.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.forum_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No threads yet',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start a new discussion',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
        : ListView.builder(
            itemCount: _threads.length,
            itemBuilder: (context, index) =>
                _threadCard(context, _threads[index]),
          );
  }

  Widget _threadCard(BuildContext context, Thread thread) {
    final lock = _lockedByThreadId[thread.id];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.chat_bubble_outline),
        title: Row(
          children: [
            Flexible(child: Text(thread.title)),
            if (lock != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: context.uiCopy(
                  zh:
                      '已被板務鎖定（${moderationReasonLabel(context, lock.reasonCode)}）',
                  en:
                      'Locked by the board moderators '
                      '(${moderationReasonLabel(context, lock.reasonCode)})',
                ),
                child: Icon(
                  Icons.lock_outline,
                  key: Key('thread_lock_icon_${thread.id}'),
                  size: 15,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'Created ${_formatDate(thread.createdAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostsViewScreen(
                db: widget.db,
                thread: thread,
                authorDid: widget.localDid,
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}
