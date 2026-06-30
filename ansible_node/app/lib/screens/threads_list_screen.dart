import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../config/app_environment.dart';
import '../services/ops_dispatch_service.dart';
import '../l10n/app_l10n.dart';
import '../l10n/moderation_copy.dart';
import '../theme/ansible_design.dart';
import '../services/app_view_timeline_client.dart';
import '../services/elix_content_link.dart';
import '../services/external_content_preferences_controller.dart';
import '../services/posting_gate.dart';
import '../services/handle_resolver.dart';
import '../widgets/author_label.dart';
import '../widgets/external_content_section.dart';
import '../widgets/posting_gate_notice.dart';
import 'thread_composer_screen.dart';
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

  /// Signs + enqueues CRDT ops for new threads/posts so they reach the relay
  /// (not just local state). When null, in-board composing stays local-only.
  final OpsDispatchService? opsDispatchService;
  final Future<void> Function()? onFlushPendingOps;

  const ThreadsListScreen({
    super.key,
    required this.db,
    required this.board,
    this.localDid,
    this.shareSheet = _defaultBoardShareSheet,
    this.externalContentPreferences,
    this.externalFetcher,
    this.opsDispatchService,
    this.onFlushPendingOps,
  });

  @override
  State<ThreadsListScreen> createState() => _ThreadsListScreenState();
}

class _ThreadsListScreenState extends State<ThreadsListScreen> {
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;
  List<Thread> _threads = [];
  bool _isLoading = true;

  /// Per-thread preview: opening post (content + signature) and reply count,
  /// for the Threads-style content-forward rows.
  final Map<String, Post?> _firstPostByThread = {};
  final Map<String, int> _replyCountByThread = {};

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
    final firstPostByThread = <String, Post?>{};
    final replyCountByThread = <String, int>{};
    for (final t in threads) {
      final posts = await _postRepo.list(threadId: t.id);
      firstPostByThread[t.id] = posts.isNotEmpty ? posts.first : null;
      // Replies = posts after the opening post.
      replyCountByThread[t.id] = posts.isEmpty ? 0 : posts.length - 1;
    }
    setState(() {
      _threads = threads;
      _hostedProjection = projection;
      _postingBlocked = postingBlocked;
      _lockedByThreadId = lockedByThreadId;
      _externalItems = externalItems;
      _firstPostByThread
        ..clear()
        ..addAll(firstPostByThread);
      _replyCountByThread
        ..clear()
        ..addAll(replyCountByThread);
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
    final dialogResult = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute(
        builder: (_) => ThreadComposerScreen(
          boards: [widget.board],
          initialBoardId: widget.board.id,
          authorDid: widget.localDid,
        ),
      ),
    );

    if (dialogResult == null) return;
    final title = dialogResult['title']?.trim();
    final boardId = dialogResult['boardId'];
    final content = dialogResult['content']?.trim() ?? '';
    final authorDid = widget.localDid;
    if (title == null ||
        title.isEmpty ||
        boardId == null ||
        boardId.isEmpty ||
        authorDid == null ||
        authorDid.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final thread = Thread(
      id: const Uuid().v4(),
      boardId: boardId,
      title: title,
      authorId: authorDid,
      createdAt: now,
      updatedAt: now,
    );
    await _threadRepo.create(thread);
    await _enqueueAndFlush(
      CrdtOpBuilder.createThread(
        authorDid: authorDid,
        entityId: thread.id,
        boardId: boardId,
        title: thread.title,
      ),
    );
    if (content.isNotEmpty) {
      final post = Post(
        id: const Uuid().v4(),
        threadId: thread.id,
        boardId: boardId,
        authorId: authorDid,
        content: content,
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
        parentPostId: null,
        signatureVerified: true, // signed locally via the ops dispatch below
      );
      await _postRepo.create(post);
      await _enqueueAndFlush(
        CrdtOpBuilder.createPost(
          authorDid: authorDid,
          entityId: post.id,
          boardId: boardId,
          threadId: thread.id,
          content: post.content,
          parentPostId: null,
        ),
      );
    }
    await _loadThreads();
  }

  Future<void> _enqueueAndFlush(OpsQueueEntry entry) async {
    final dispatchService = widget.opsDispatchService;
    if (dispatchService == null) return;
    await dispatchService.signAndEnqueue(entry);
    final flushPendingOps = widget.onFlushPendingOps;
    if (flushPendingOps == null) {
      unawaited(dispatchService.flushPending());
    } else {
      unawaited(flushPendingOps());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AnsibleDesign.paper,
      appBar: AppBar(
        title: Text(
          widget.board.title,
          style: const TextStyle(
            color: AnsibleDesign.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AnsibleDesign.paper,
        foregroundColor: AnsibleDesign.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
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
        backgroundColor: _postingBlocked
            ? AnsibleDesign.paperDeep
            : AnsibleDesign.ink,
        foregroundColor: _postingBlocked
            ? AnsibleDesign.inkFaint
            : AnsibleDesign.paper,
        elevation: 1,
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
                const Icon(
                  Icons.forum_outlined,
                  size: 56,
                  color: AnsibleDesign.inkFaint,
                ),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(zh: '還沒有討論串', en: 'No threads yet'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.uiCopy(
                    zh: '點右下角 + 開始一個新討論',
                    en: 'Tap + to start a discussion',
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: _threads.length,
            itemBuilder: (context, index) =>
                _threadCard(context, _threads[index]),
          );
  }

  Widget _threadCard(BuildContext context, Thread thread) {
    final lock = _lockedByThreadId[thread.id];
    final firstPost = _firstPostByThread[thread.id];
    final preview = firstPost?.content.trim() ?? '';
    final signed = firstPost?.signatureVerified ?? false;
    final replies = _replyCountByThread[thread.id] ?? 0;
    final title = thread.title.trim();

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostsViewScreen(
              db: widget.db,
              thread: thread,
              authorDid: widget.localDid,
              opsDispatchService: widget.opsDispatchService,
              onFlushPendingOps: widget.onFlushPendingOps,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<String?>(
              initialData: HandleResolver.shared.cached(thread.authorId),
              future: HandleResolver.shared.handleFor(thread.authorId),
              builder: (context, snap) {
                final h = (snap.data ?? '').replaceFirst('@', '').trim();
                final initial =
                    h.isEmpty ? '·' : h.substring(0, 1).toUpperCase();
                return Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AnsibleDesign.paperDeep,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AuthorLabel(
                          did: thread.authorId,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                      ),
                      if (signed) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: context.uiCopy(
                            zh: '簽章已驗證',
                            en: 'Signature verified',
                          ),
                          child: const Icon(
                            Icons.verified_user,
                            size: 12,
                            color: AnsibleDesign.spore,
                          ),
                        ),
                      ],
                      if (lock != null) ...[
                        const SizedBox(width: 4),
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
                            size: 13,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        '· ${_shortTime(context, thread.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  if (title.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: AnsibleDesign.ink,
                      ),
                    ),
                  ],
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.mode_comment_outlined,
                        size: 14,
                        color: AnsibleDesign.inkFaint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$replies',
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 11,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact relative timestamp for the byline (Threads-style: "3 小時" / "3h").
  String _shortTime(BuildContext context, DateTime date) {
    final d = DateTime.now().difference(date);
    if (d.inDays > 7) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    if (d.inDays > 0) {
      return context.uiCopy(zh: '${d.inDays} 天', en: '${d.inDays}d');
    }
    if (d.inHours > 0) {
      return context.uiCopy(zh: '${d.inHours} 小時', en: '${d.inHours}h');
    }
    if (d.inMinutes > 0) {
      return context.uiCopy(zh: '${d.inMinutes} 分', en: '${d.inMinutes}m');
    }
    return context.uiCopy(zh: '剛剛', en: 'now');
  }
}
