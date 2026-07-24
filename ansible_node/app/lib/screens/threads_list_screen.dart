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
import '../theme/elix_screen_style.dart';
import '../services/app_view_timeline_client.dart';
import '../services/elix_content_link.dart';
import '../services/external_content_preferences_controller.dart';
import '../services/forum_publication_service.dart';
import '../services/posting_gate.dart';
import '../services/private_board_op_factory.dart';
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

Future<void> _defaultBoardShareSheet(
  String text, {
  String? subject,
  Rect? sharePositionOrigin,
}) {
  return Share.share(
    text,
    subject: subject,
    sharePositionOrigin: sharePositionOrigin,
  );
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

  /// The board's screen style (Paper/Ink) so a pushed board follows the
  /// dark/light choice made for the Forum board.
  final ElixScreenStyle screenStyle;

  /// Records hosted-board publication targets (primary + cross-posts) for
  /// new threads. Injectable for tests; defaults to a drift-backed service.
  final ForumPublicationService? forumPublicationService;

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
    this.screenStyle = ElixScreenStyle.paper,
    this.forumPublicationService,
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

  /// Per-thread last activity: timestamp of the most recent post (the opening
  /// post when there are no replies yet). Drives the "最後回應" byline.
  final Map<String, DateTime> _lastActivityByThread = {};

  /// The tier this board requires to post (null = open to anyone). Drives the
  /// board header card's posting-policy chip; [_postingBlocked] says whether the
  /// local user clears it.
  String? _requiredTier;

  /// Host moderation overlay: lock entries keyed by thread id (reason-coded).
  Map<String, HostModerationState> _lockedByThreadId = const {};

  /// Set when this board is hosted by a Forum Host; only hosted boards have a
  /// public web URL to share.
  HostedBoardProjection? _hostedProjection;
  RemoteTombstone? _remoteRemoval;

  /// True when the board requires a higher tier than the local user has.
  /// Client-side UX only — the relay re-checks at intent acceptance.
  bool _postingBlocked = false;

  /// Curated external (fediverse) items for this board, fetched ONLY when both
  /// gates pass (board.externalInclusion AND the user opt-in). Empty otherwise.
  List<AppViewExternalItem> _externalItems = const [];

  late final ExternalContentPreferencesController _externalPrefs;

  // Brightness-aware palette derived from the board's screen style, so E15
  // follows the Forum board's Paper/Ink choice.
  bool get _dark {
    switch (widget.screenStyle) {
      case ElixScreenStyle.ink:
        return true;
      case ElixScreenStyle.paper:
        return false;
      case ElixScreenStyle.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  Color get _bg => _dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
  Color get _deep =>
      _dark ? AnsibleDesign.darkPaperDeep : AnsibleDesign.paperDeep;
  Color get _fg => _dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
  Color get _muted =>
      _dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
  Color get _faint =>
      _dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
  Color get _rule => _dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
  Color get _ruleSoft =>
      _dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
  Color get _accent => _dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent;
  Color get _moss => _dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss;

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
    final remoteRemoval = projection == null
        ? null
        : await DriftRemoteTombstoneRepository(
            widget.db,
          ).get(projection.forumHostId, 'board', projection.hostedBoardId);
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
    final lastActivityByThread = <String, DateTime>{};
    for (final t in threads) {
      final posts = await _postRepo.list(threadId: t.id);
      firstPostByThread[t.id] = posts.isNotEmpty ? posts.first : null;
      // Replies = posts after the opening post.
      replyCountByThread[t.id] = posts.isEmpty ? 0 : posts.length - 1;
      // Last activity = most recent post, else the thread's own timestamp.
      lastActivityByThread[t.id] = posts.isEmpty
          ? t.createdAt
          : posts
                .map((p) => p.createdAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
    }
    setState(() {
      _threads = threads;
      _hostedProjection = projection;
      _remoteRemoval = remoteRemoval;
      _postingBlocked = postingBlocked;
      _requiredTier = projection?.minPostTier;
      _lockedByThreadId = lockedByThreadId;
      _externalItems = externalItems;
      _firstPostByThread
        ..clear()
        ..addAll(firstPostByThread);
      _replyCountByThread
        ..clear()
        ..addAll(replyCountByThread);
      _lastActivityByThread
        ..clear()
        ..addAll(lastActivityByThread);
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
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await widget.shareSheet(
      url,
      subject: widget.board.title,
      sharePositionOrigin: origin,
    );
  }

  Future<void> _createThread() async {
    final dialogResult = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => ThreadComposerScreen(
          boards: [widget.board],
          initialBoardId: widget.board.id,
          authorDid: widget.localDid,
          db: widget.db,
        ),
      ),
    );

    if (dialogResult == null) return;
    final title = (dialogResult['title'] as String?)?.trim();
    final boardId = dialogResult['boardId'] as String?;
    final content = (dialogResult['content'] as String?)?.trim() ?? '';
    final crossPostTargetIds =
        (dialogResult['crossPostTargetIds'] as List?)?.cast<String>() ??
        const <String>[];
    final publicationDeferred =
        dialogResult['publicationDeferred'] as bool? ?? false;
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
    final projection = _hostedProjection;
    await _enqueueAndFlush(
      projection?.contentVisibility == 'end_to_end_encrypted'
          ? await PrivateBoardOpFactory().createThread(
              board: projection!,
              authorDid: authorDid,
              entityId: thread.id,
              title: thread.title,
              createdAt: now,
            )
          : CrdtOpBuilder.createThread(
              authorDid: authorDid,
              entityId: thread.id,
              boardId: boardId,
              title: thread.title,
            ),
      deferPublication: publicationDeferred,
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
        projection?.contentVisibility == 'end_to_end_encrypted'
            ? await PrivateBoardOpFactory().createPost(
                board: projection!,
                authorDid: authorDid,
                entityId: post.id,
                threadId: thread.id,
                content: post.content,
                parentPostId: null,
                createdAt: now,
              )
            : CrdtOpBuilder.createPost(
                authorDid: authorDid,
                entityId: post.id,
                boardId: boardId,
                threadId: thread.id,
                content: post.content,
                parentPostId: null,
              ),
        deferPublication: publicationDeferred,
      );
    }
    await _recordPublicationTargets(
      threadId: thread.id,
      boardId: boardId,
      crossPostTargetIds: crossPostTargetIds,
    );
    await _loadThreads();
  }

  /// Records hosted-board publication targets for the new thread (primary +
  /// selected cross-posts) and surfaces a non-blocking notice when some
  /// cross-post targets were rejected (e.g. write access revoked since the
  /// composer was opened). Never blocks the primary publication.
  Future<void> _recordPublicationTargets({
    required String threadId,
    required String boardId,
    required List<String> crossPostTargetIds,
  }) async {
    final service =
        widget.forumPublicationService ??
        ForumPublicationService(
          hostedBoards: DriftHostedBoardRepository(widget.db),
        );
    final result = await service.createThreadForLocalBoard(
      localDraftId: threadId,
      primaryLocalBoardId: boardId,
      crossPostTargetIds: crossPostTargetIds,
    );
    if (result == null) return;
    final failedCrossPosts = result.rejectedTargetIds
        .where(crossPostTargetIds.contains)
        .toList();
    if (failedCrossPosts.isEmpty) return;
    final titles = await service.boardTitlesForTargets(
      DriftBoardRepository(widget.db),
      failedCrossPosts,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '部分看板未能同時發佈：${titles.join('、')}',
            en: 'Could not cross-post to: ${titles.join(', ')}',
          ),
        ),
      ),
    );
  }

  Future<void> _enqueueAndFlush(
    OpsQueueEntry entry, {
    bool deferPublication = false,
  }) async {
    final dispatchService = widget.opsDispatchService;
    if (dispatchService == null) return;
    await dispatchService.signAndEnqueue(entry);
    if (deferPublication) return;
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
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          _boardHashtag,
          style: TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 16,
            color: _fg,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _bg,
        foregroundColor: _fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (_boardShareUrl != null)
            IconButton(
              key: const Key('share_board_button'),
              icon: Icon(Icons.ios_share, size: 21),
              tooltip: context.uiCopy(zh: '分享看板', en: 'Share board'),
              onPressed: _shareBoard,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_remoteRemoval != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    color: _deep,
                    child: Text(
                      context.uiCopy(
                        zh: '原主機已移除此看板；本機看板與貼文仍完整保留。',
                        en: 'The original host removed this board. Your local board and posts are preserved.',
                      ),
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        color: _muted,
                      ),
                    ),
                  ),
                if (_postingBlocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: PostingGateNotice(
                      localDid: widget.localDid ?? '',
                      onUpgradeCompleted: _loadThreads,
                    ),
                  ),
                Expanded(child: _threadsBody(context)),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _postingBlocked ? null : _createThread,
        tooltip: _postingBlocked
            ? context.uiCopy(zh: '需通過真人驗證才能發文', en: 'Verified humans only')
            : context.uiCopy(zh: '建立討論串', en: 'Create thread'),
        backgroundColor: _postingBlocked ? _deep : _fg,
        foregroundColor: _postingBlocked ? _faint : _bg,
        elevation: 1,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _threadsBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        _boardHeaderCard(context),
        const SizedBox(height: 12),
        if (_threads.isEmpty)
          _emptyHint(context)
        else
          for (final thread in _threads) ...[
            _threadCard(context, thread),
            const SizedBox(height: 10),
          ],
        if (_externalItems.isNotEmpty)
          ExternalContentSection(items: _externalItems),
      ],
    );
  }

  /// E·15 board header: a "section-block" carrying the board's kicker,
  /// description, thread count, and posting policy.
  Widget _boardHeaderCard(BuildContext context) {
    final description = widget.board.description?.trim() ?? '';
    final threadCount = _threads.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _bg,
        border: Border.all(color: _rule, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.uiCopy(zh: '看板', en: 'Board')} · ${widget.board.title}',
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              letterSpacing: 1.4,
              color: _accent,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 13,
                height: 1.55,
                color: _muted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _ruleSoft, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  context.uiCopy(
                    zh: '$threadCount 串',
                    en: '$threadCount ${threadCount == 1 ? 'thread' : 'threads'}',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: _faint,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  _postingPolicyLabel(context),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mono policy chip for the header card, reflecting the real posting gate.
  String _postingPolicyLabel(BuildContext context) {
    if (_requiredTier == null) {
      return context.uiCopy(zh: '公開 · 可發文', en: 'OPEN · POST FREELY');
    }
    if (_postingBlocked) {
      return context.uiCopy(zh: '需真人驗證 · 暫不可發文', en: 'VERIFIED ONLY · LOCKED');
    }
    return context.uiCopy(zh: '需真人驗證 · 可發文', en: 'VERIFIED · CAN POST');
  }

  Widget _emptyHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 48, color: _faint),
          const SizedBox(height: 14),
          Text(
            context.uiCopy(zh: '還沒有討論串', en: 'No threads yet'),
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.uiCopy(
              zh: '點右下角 + 開始一個新討論',
              en: 'Tap + to start a discussion',
            ),
            style: TextStyle(fontSize: 13, color: _faint),
          ),
        ],
      ),
    );
  }

  /// E·15 thread card: a "post" with a mono source strip, a serif title, and an
  /// author row carrying the avatar, byline, and last-activity time.
  Widget _threadCard(BuildContext context, Thread thread) {
    final lock = _lockedByThreadId[thread.id];
    final firstPost = _firstPostByThread[thread.id];
    final signed = firstPost?.signatureVerified ?? false;
    final replies = _replyCountByThread[thread.id] ?? 0;
    final title = thread.title.trim();
    final lastActivity = _lastActivityByThread[thread.id] ?? thread.createdAt;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostsViewScreen(
              db: widget.db,
              thread: thread,
              openingPost: firstPost,
              authorDid: widget.localDid,
              opsDispatchService: widget.opsDispatchService,
              onFlushPendingOps: widget.onFlushPendingOps,
              screenStyle: widget.screenStyle,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: _bg,
          border: Border.all(color: _rule, width: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // post-source: pip + reply count + status.
            Container(
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _ruleSoft, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _moss,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$replies ${context.uiCopy(zh: '回應', en: replies == 1 ? 'REPLY' : 'REPLIES')}'
                    ' · '
                    '${replies > 0 ? context.uiCopy(zh: '進行中', en: 'ACTIVE') : context.uiCopy(zh: '新討論', en: 'NEW')}',
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 8.5,
                      letterSpacing: 1.2,
                      color: _faint,
                    ),
                  ),
                ],
              ),
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 17,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: _fg,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // post-author: avatar + name (+ sig/lock) + last-activity byline.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _authorAvatar(thread.authorId, signed),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: AuthorLabel(
                              did: thread.authorId,
                              style: TextStyle(
                                fontFamily: AnsibleDesign.serif,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _fg,
                              ),
                            ),
                          ),
                          if (signed) ...[
                            const SizedBox(width: 5),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                          if (lock != null) ...[
                            const SizedBox(width: 5),
                            Tooltip(
                              message: context.uiCopy(
                                zh: '已被板務鎖定（${moderationReasonLabel(context, lock.reasonCode)}）',
                                en:
                                    'Locked by the board moderators '
                                    '(${moderationReasonLabel(context, lock.reasonCode)})',
                              ),
                              child: Icon(
                                Icons.lock_outline,
                                key: Key('thread_lock_icon_${thread.id}'),
                                size: 13,
                                color: _faint,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        replies > 0
                            ? context.uiCopy(
                                zh: '最後回應 · ${_shortTime(context, lastActivity)}',
                                en: 'LAST REPLY · ${_shortTime(context, lastActivity)}',
                              )
                            : context.uiCopy(
                                zh: '起頭 · ${_shortTime(context, lastActivity)}',
                                en: 'STARTED · ${_shortTime(context, lastActivity)}',
                              ),
                        style: TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 9,
                          letterSpacing: 0.5,
                          color: _faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 30px circular initial avatar — amber when the opening post is signed,
  /// matching the feed and board-card treatment.
  Widget _authorAvatar(String did, bool signed) {
    return FutureBuilder<String?>(
      initialData: HandleResolver.shared.cached(did),
      future: HandleResolver.shared.handleFor(did),
      builder: (context, snap) {
        final h = (snap.data ?? '').replaceFirst('@', '').trim();
        final initial = h.isEmpty ? '·' : h.substring(0, 1).toUpperCase();
        return Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: signed ? _accent : _deep,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: signed ? _bg : _muted,
            ),
          ),
        );
      },
    );
  }

  /// The board title rendered as a hashtag for the header (E·15 "# philosophy").
  String get _boardHashtag {
    final raw = widget.board.title.trim();
    final stripped = raw.replaceFirst(RegExp(r'^[#＃]\s*'), '');
    return '# $stripped';
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
