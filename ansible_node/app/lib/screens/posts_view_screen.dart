import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_l10n.dart';
import '../l10n/moderation_copy.dart';
import '../l10n/user_facing_error.dart';
import '../services/elix_content_link.dart';
import '../services/forum_host_client.dart';
import '../services/ops_dispatch_service.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import '../services/handle_resolver.dart';
import '../widgets/author_label.dart';
import 'post_composer_screen.dart';
import '../widgets/posting_gate_notice.dart';
import '../widgets/report_dialog.dart';

/// Seam for invoking the platform share sheet. Defaults to share_plus; tests
/// inject a fake to assert the constructed URL without a real share sheet.
typedef ShareSheet = Future<void> Function(String text, {String? subject});

Future<void> _defaultShareSheet(String text, {String? subject}) {
  return Share.share(text, subject: subject);
}

class PostsViewScreen extends StatefulWidget {
  final AppDatabase db;
  final Thread thread;
  final Post? openingPost;
  final String? authorDid;
  final OpsDispatchService? opsDispatchService;
  final Future<void> Function()? onFlushPendingOps;

  /// Platform share-sheet seam (overridable in tests).
  final ShareSheet shareSheet;

  /// Follows the originating board's Paper/Ink choice.
  final ElixScreenStyle screenStyle;

  /// Test seam: builds the Forum Host client used to submit reports.
  /// Defaults to a real [ForumHostClient] against the board's host URL.
  final ForumHostClient Function(String baseUrl)? reportClientFactory;

  /// Test seam: signs the canonical report payload with the local DID key.
  /// Defaults to [DidSignerImpl] (secure-storage key + Rust core).
  final Future<String> Function(List<int> payload)? reportPayloadSigner;

  const PostsViewScreen({
    super.key,
    required this.db,
    required this.thread,
    this.openingPost,
    this.authorDid,
    this.opsDispatchService,
    this.onFlushPendingOps,
    this.shareSheet = _defaultShareSheet,
    this.screenStyle = ElixScreenStyle.paper,
    this.reportClientFactory,
    this.reportPayloadSigner,
  });

  @override
  State<PostsViewScreen> createState() => _PostsViewScreenState();
}

class _PostsViewScreenState extends State<PostsViewScreen> {
  late final DriftPostRepository _postRepo;
  List<Post> _posts = [];
  bool _isLoading = true;

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

  /// True when the board requires a higher tier than the local user has.
  /// Client-side UX only — the relay re-checks at intent acceptance.
  bool _postingBlocked = false;

  /// Set when this thread's board is hosted by a Forum Host; reporting is
  /// only possible for hosted content (local-only boards have no moderator).
  HostedBoardProjection? _hostedProjection;
  Board? _board;

  /// Host moderation overlay (synced snapshot): the lock entry for this
  /// thread, if any, and removal entries keyed by post id. Host-scoped
  /// projection only — local content rows are never touched.
  HostModerationState? _threadLock;
  Map<String, HostModerationState> _removedByPostId = const {};
  RemoteTombstone? _remoteRemoval;

  String get _authorDid => widget.authorDid ?? widget.thread.authorId;

  @override
  void initState() {
    super.initState();
    _postRepo = DriftPostRepository(widget.db);
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    final posts = [...await _postRepo.list(threadId: widget.thread.id)];
    final openingPost = widget.openingPost;
    if (openingPost != null &&
        !posts.any((post) => post.id == openingPost.id)) {
      posts.insert(0, openingPost);
    }
    if (posts.isEmpty) {
      // Legacy/local-first data may contain a canonical Thread created before
      // opening posts were stored as separate Post rows. The thread itself is
      // still real user content, so render it as a read-only OP rather than
      // claiming that no post exists.
      posts.add(
        Post(
          id: '${widget.thread.id}:legacy-opening',
          threadId: widget.thread.id,
          boardId: widget.thread.boardId,
          authorId: widget.thread.authorId,
          content: '',
          createdAt: widget.thread.createdAt,
          updatedAt: widget.thread.updatedAt,
          lastEditAt: widget.thread.updatedAt,
        ),
      );
    }
    final board = await DriftBoardRepository(
      widget.db,
    ).getById(widget.thread.boardId);
    final projection = await DriftHostedBoardRepository(
      widget.db,
    ).getProjectionByLocalBoardId(widget.thread.boardId);
    final postingBlocked = await _checkPostingGate(projection);
    final remoteRemoval = projection == null
        ? null
        : await DriftRemoteTombstoneRepository(
            widget.db,
          ).get(projection.forumHostId, 'thread', widget.thread.id);
    final moderationEntries = await DriftHostModerationStateRepository(
      widget.db,
    ).listForBoard(widget.thread.boardId);
    HostModerationState? threadLock;
    final removedByPostId = <String, HostModerationState>{};
    for (final entry in moderationEntries) {
      if (entry.targetKind == HostModerationState.targetKindThread &&
          entry.targetRef == widget.thread.id &&
          entry.action == HostModerationState.actionLocked) {
        threadLock = entry;
      } else if (entry.targetKind == HostModerationState.targetKindPost &&
          entry.action == HostModerationState.actionRemoved) {
        removedByPostId[entry.targetRef] = entry;
      }
    }
    setState(() {
      _posts = posts;
      _board = board;
      _hostedProjection = projection;
      _postingBlocked = postingBlocked;
      _threadLock = threadLock;
      _removedByPostId = removedByPostId;
      _remoteRemoval = remoteRemoval;
      _isLoading = false;
    });
  }

  Future<bool> _checkPostingGate(HostedBoardProjection? projection) async {
    final requiredTier = projection?.minPostTier;
    if (requiredTier == null) return false;
    final tier = await DriftDidReputationRepository(
      widget.db,
    ).tierFor(_authorDid);
    return !PostingGate.satisfies(tier, requiredTier);
  }

  /// Public web URL for this thread on the distribution frontend, or null when
  /// the board is not hosted (local-only content has no public URL to share).
  String? get _threadShareUrl {
    final projection = _hostedProjection;
    if (projection == null) return null;
    return ElixContentLink.threadUrl(
      canonicalBoardUri: projection.canonicalBoardUri,
      boardId: projection.hostedBoardId,
      threadId: widget.thread.id,
    );
  }

  /// Opens the platform share sheet with this thread's public web URL so it can
  /// be pasted into LINE / Threads / Messenger (the outbound growth loop). The
  /// shared link renders a rich preview via the frontend's Open Graph tags.
  Future<void> _shareThread() async {
    final url = _threadShareUrl;
    if (url == null) return;
    await widget.shareSheet(url, subject: widget.thread.title);
  }

  /// Reports a post (or, with [post] null, the thread itself) to the Forum
  /// Host that owns this board, as a signed `report_content` intent.
  Future<void> _reportContent({Post? post}) async {
    final projection = _hostedProjection;
    if (projection == null) return;
    final host = await DriftRemoteNodeRepository(
      widget.db,
    ).getById(projection.forumHostId);
    if (host == null || !mounted) return;

    final draft = await showReportDialog(context);
    if (draft == null || !mounted) return;

    final intentId = const Uuid().v4();
    final createdAt = DateTime.now().toUtc();
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final canonicalPayload = ReportContentIntent.canonicalPayload(
      intentId: intentId,
      authorDid: _authorDid,
      targetForumHost: host.url,
      targetKind: post == null ? 'thread' : 'post',
      targetRef: post?.id ?? widget.thread.id,
      boardId: projection.hostedBoardId,
      reasonCode: draft.reasonCode,
      note: draft.note,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
    try {
      final signature = await _signReportPayload(
        utf8.encode(jsonEncode(canonicalPayload)),
      );
      final client =
          (widget.reportClientFactory ??
          (baseUrl) => ForumHostClient(baseUrl: baseUrl))(host.url);
      final ReportSubmission submission;
      try {
        submission = await client.submitReport(
          ReportContentIntent(
            intentId: intentId,
            authorDid: _authorDid,
            targetForumHost: host.url,
            signature: signature,
            targetKind: post == null ? 'thread' : 'post',
            targetRef: post?.id ?? widget.thread.id,
            boardId: projection.hostedBoardId,
            reasonCode: draft.reasonCode,
            note: draft.note,
            createdAt: createdAt,
            expiresAt: expiresAt,
          ),
        );
      } finally {
        client.close();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            submission.duplicate
                ? context.uiCopy(
                    zh: '你已檢舉過這則內容，板務處理中',
                    en: 'Already reported; the moderators are on it',
                  )
                : context.uiCopy(
                    zh: '已送出檢舉，將由板務依板規處理',
                    en: 'Report submitted to the board moderators',
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    }
  }

  Future<String> _signReportPayload(List<int> payload) {
    final signer = widget.reportPayloadSigner;
    if (signer != null) return signer(payload);
    return DidSignerImpl().sign(payload).then((signature) => signature.hex);
  }

  Future<void> _createPost() async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PostComposerScreen(authorDid: _authorDid),
      ),
    );

    if (content != null) {
      final now = DateTime.now();
      final post = Post(
        id: const Uuid().v4(),
        threadId: widget.thread.id,
        boardId: widget.thread.boardId,
        authorId: _authorDid,
        content: content,
        createdAt: now,
        updatedAt: now,
        lastEditAt: now,
        signatureVerified: true, // signed locally via the ops dispatch below
      );
      await _postRepo.create(post);
      await _enqueueAndFlush(
        CrdtOpBuilder.createPost(
          authorDid: _authorDid,
          entityId: post.id,
          boardId: post.boardId,
          threadId: post.threadId,
          content: post.content,
          parentPostId: post.parentPostId,
        ),
      );
      _loadPosts();
    }
  }

  Future<void> _editPost(Post post) async {
    final content = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PostComposerScreen(
          initialContent: post.content,
          authorDid: _authorDid,
        ),
      ),
    );

    if (content != null) {
      final now = DateTime.now();
      final updatedPost = Post(
        id: post.id,
        threadId: post.threadId,
        boardId: post.boardId,
        authorId: post.authorId,
        content: content,
        createdAt: post.createdAt,
        updatedAt: now,
        lastEditAt: now,
        parentPostId: post.parentPostId,
        isDeleted: post.isDeleted,
        signatureVerified: true, // re-signed via the update op below
      );
      await _postRepo.update(updatedPost);
      await _enqueueAndFlush(
        CrdtOpBuilder.updatePost(
          authorDid: _authorDid,
          entityId: updatedPost.id,
          newContent: updatedPost.content,
        ),
      );
      _loadPosts();
    }
  }

  Future<void> _deletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.uiCopy(zh: '刪除貼文', en: 'Delete Post')),
        content: Text(
          context.uiCopy(
            zh: '確定要刪除這則貼文嗎？',
            en: 'Are you sure you want to delete this post?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.uiCopy(zh: '刪除', en: 'Delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _postRepo.delete(post.id);
      await _enqueueAndFlush(
        CrdtOpBuilder.deletePost(authorDid: _authorDid, entityId: post.id),
      );
      _loadPosts();
    }
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 92,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.chevron_left, size: 22, color: _muted),
          label: Text(
            context.uiCopy(zh: '返回', en: 'Back'),
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 14,
              color: _muted,
            ),
          ),
        ),
        title: Text(
          context.uiCopy(zh: '貼文', en: 'POST'),
          style: TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 12,
            letterSpacing: 2,
            color: _muted,
          ),
        ),
        actions: [
          if (_threadShareUrl != null)
            IconButton(
              key: const Key('share_thread_button'),
              icon: Icon(Icons.ios_share, size: 21),
              tooltip: context.uiCopy(zh: '分享討論串', en: 'Share thread'),
              onPressed: _shareThread,
            ),
          if (_hostedProjection != null && widget.thread.authorId != _authorDid)
            IconButton(
              key: const Key('report_thread_button'),
              icon: Icon(Icons.outlined_flag, size: 21),
              tooltip: context.uiCopy(zh: '檢舉討論串', en: 'Report thread'),
              onPressed: () => _reportContent(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_remoteRemoval != null) _remoteRemovalBanner(context),
                if (_threadLock != null)
                  _threadLockedBanner(context, _threadLock!),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: _threadItems(context),
                  ),
                ),
                _composerBar(context),
              ],
            ),
    );
  }

  Widget _remoteRemovalBanner(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    color: _deep,
    child: Text(
      context.uiCopy(
        zh: '原主機已移除此討論；本機副本仍完整保留。',
        en: 'The original host removed this discussion. Your local copy is preserved.',
      ),
      style: TextStyle(
        fontFamily: AnsibleDesign.serif,
        fontSize: 13,
        color: _muted,
      ),
    ),
  );

  List<Widget> _threadItems(BuildContext context) {
    final items = <Widget>[];
    if (_posts.isEmpty) {
      items.add(_emptyState(context));
      return items;
    }
    items.add(_opPost(context, _posts.first));
    final replies = _posts.skip(1).toList();
    items.add(_replyHead(context, replies.length));
    for (final r in replies) {
      items.add(_replyRow(context, r));
    }
    return items;
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.message_outlined, size: 48, color: _faint),
          const SizedBox(height: 14),
          Text(
            context.uiCopy(zh: '還沒有貼文', en: 'No posts yet'),
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.uiCopy(zh: '搶先發表第一則貼文', en: 'Be the first to post'),
            style: TextStyle(fontSize: 13, color: _faint),
          ),
        ],
      ),
    );
  }

  /// Initial-letter avatar; amber when the post's op is signed.
  Widget _avatar(String did, {required double size, required bool signed}) {
    return FutureBuilder<String?>(
      initialData: HandleResolver.shared.cached(did),
      future: HandleResolver.shared.handleFor(did),
      builder: (context, snap) {
        final h = (snap.data ?? '').replaceFirst('@', '').trim();
        final initial = h.isEmpty ? '·' : h.substring(0, 1).toUpperCase();
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: signed ? _accent : _deep,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w500,
              color: signed ? _bg : _muted,
            ),
          ),
        );
      },
    );
  }

  /// Opening post (posts.first): large body + full action row.
  Widget _opPost(BuildContext context, Post post) {
    final removal = _removedByPostId[post.id];
    if (removal != null && post.authorId != _authorDid) {
      return _removedPostTombstone(context, post, removal);
    }
    final edited = post.lastEditAt.isAfter(post.createdAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _rule, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(post.authorId, size: 40, signed: post.signatureVerified),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: AuthorLabel(
                            did: post.authorId,
                            style: TextStyle(
                              fontFamily: AnsibleDesign.sans,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: _fg,
                            ),
                          ),
                        ),
                        if (post.signatureVerified) ...[
                          const SizedBox(width: 5),
                          Icon(Icons.verified, size: 14, color: _accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    _opSub(context, post, edited),
                  ],
                ),
              ),
              _postMenu(context, post),
            ],
          ),
          if (removal != null) ...[
            const SizedBox(height: 8),
            _ownPostRemovalNotice(context, removal),
          ],
          const SizedBox(height: 12),
          if ((_board?.slug ?? _board?.title ?? '').trim().isNotEmpty) ...[
            Text(
              '# ${(_board?.slug ?? _board?.title ?? '').trim()}',
              key: const Key('thread_board_crumb'),
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 10,
                letterSpacing: 1.3,
                color: _accent,
              ),
            ),
            const SizedBox(height: 5),
          ],
          Text(
            widget.thread.title,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: _fg,
            ),
          ),
          if (post.content.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              post.content,
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 16,
                height: 1.78,
                color: _fg,
              ),
            ),
          ],
          if (removal == null) ...[
            const SizedBox(height: 6),
            _opActions(context, post),
          ],
        ],
      ),
    );
  }

  /// "13 小時 · signed · 起頭" byline for the opening post.
  Widget _opSub(BuildContext context, Post post, bool edited) {
    final base = TextStyle(
      fontFamily: AnsibleDesign.sans,
      fontSize: 12,
      color: _faint,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: _formatDate(context, post.createdAt)),
          if (post.signatureVerified) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: context.uiCopy(zh: '已簽署', en: 'signed'),
              style: TextStyle(color: _accent),
            ),
          ],
          TextSpan(
            text: ' · ${context.uiCopy(zh: '起頭', en: 'OP')}',
          ),
          if (edited)
            TextSpan(
              text: context.uiCopy(zh: '（已編輯）', en: ' (edited)'),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Threads-style OP action row: heart · comment · repost · share.
  Widget _opActions(BuildContext context, Post post) {
    final replyCount = (_posts.length - 1).clamp(0, 1 << 30);
    return Row(
      children: [
        _PostReactionBar(
          key: ValueKey('post_reactions_${post.id}'),
          db: widget.db,
          postId: post.id,
          localDid: widget.authorDid,
          opsDispatchService: widget.opsDispatchService,
          onFlushPendingOps: widget.onFlushPendingOps,
          dark: _dark,
        ),
        const SizedBox(width: 22),
        _actionIcon(
          Icons.mode_comment_outlined,
          count: replyCount,
          onTap: _createPost,
        ),
        const SizedBox(width: 22),
        _actionIcon(Icons.repeat, onTap: _shareThread),
        const Spacer(),
        _actionIcon(Icons.send_outlined, onTap: _shareThread),
      ],
    );
  }

  Widget _actionIcon(IconData icon, {int? count, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: _muted),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: AnsibleDesign.sans,
                fontSize: 13,
                color: _muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "N 則回應 · 依時間" divider above the reply list.
  Widget _replyHead(BuildContext context, int replyCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 4),
      child: Row(
        children: [
          Text(
            context.uiCopy(zh: '$replyCount 則回應', en: '$replyCount replies'),
            style: TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _fg,
            ),
          ),
          Text(
            ' · ${context.uiCopy(zh: '依時間', en: 'by time')}',
            style: TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 13,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }

  /// A single reply row.
  Widget _replyRow(BuildContext context, Post post) {
    final removal = _removedByPostId[post.id];
    if (removal != null && post.authorId != _authorDid) {
      return _removedPostTombstone(context, post, removal);
    }
    final edited = post.lastEditAt.isAfter(post.createdAt);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(post.authorId, size: 34, signed: post.signatureVerified),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: AuthorLabel(
                        did: post.authorId,
                        style: TextStyle(
                          fontFamily: AnsibleDesign.sans,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _fg,
                        ),
                      ),
                    ),
                    if (post.signatureVerified) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.verified, size: 13, color: _accent),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(context, post.createdAt) +
                          (edited
                              ? context.uiCopy(zh: '（已編輯）', en: ' (edited)')
                              : ''),
                      style: TextStyle(
                        fontFamily: AnsibleDesign.sans,
                        fontSize: 12,
                        color: _faint,
                      ),
                    ),
                    const Spacer(),
                    _postMenu(context, post),
                  ],
                ),
                if (removal != null) ...[
                  const SizedBox(height: 6),
                  _ownPostRemovalNotice(context, removal),
                ],
                const SizedBox(height: 5),
                Text(
                  post.content,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14.5,
                    height: 1.68,
                    color: _fg,
                  ),
                ),
                if (removal == null) ...[
                  const SizedBox(height: 8),
                  _PostReactionBar(
                    key: ValueKey('post_reactions_${post.id}'),
                    db: widget.db,
                    postId: post.id,
                    localDid: widget.authorDid,
                    opsDispatchService: widget.opsDispatchService,
                    onFlushPendingOps: widget.onFlushPendingOps,
                    dark: _dark,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Per-post overflow menu (edit / delete / report).
  Widget _postMenu(BuildContext context, Post post) {
    return SizedBox(
      height: 22,
      width: 28,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz, size: 18, color: _faint),
        itemBuilder: (context) => [
          if (post.authorId == _authorDid) ...[
            PopupMenuItem(
              value: 'edit',
              child: Text(context.uiCopy(zh: '編輯', en: 'Edit')),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                context.uiCopy(zh: '刪除', en: 'Delete'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
          if (_hostedProjection != null && post.authorId != _authorDid)
            PopupMenuItem(
              value: 'report',
              child: Text(context.uiCopy(zh: '檢舉', en: 'Report')),
            ),
        ],
        onSelected: (value) {
          if (value == 'edit') {
            _editPost(post);
          } else if (value == 'delete') {
            _deletePost(post);
          } else if (value == 'report') {
            _reportContent(post: post);
          }
        },
      ),
    );
  }

  /// e16 reply composer bar: your avatar + a tap-to-reply field + send.
  Widget _composerBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _ruleSoft, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: SafeArea(
        top: false,
        child: _threadLock != null
            ? _lockedComposerNotice(context, _threadLock!)
            : _postingBlocked
            ? PostingGateNotice(
                localDid: _authorDid,
                onUpgradeCompleted: _loadPosts,
              )
            : Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _createPost,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _rule, width: 1),
                        ),
                        child: Text(
                          context.uiCopy(
                            zh: '回覆這則討論…',
                            en: 'Reply to this thread…',
                          ),
                          style: TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontStyle: FontStyle.italic,
                            fontSize: 14,
                            color: _faint,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const Key('new_post_button'),
                    onPressed: _createPost,
                    icon: Icon(Icons.send, size: 20, color: _fg),
                  ),
                ],
              ),
      ),
    );
  }

  /// Reason-coded banner shown to everyone while the host has this thread
  /// locked.
  Widget _threadLockedBanner(BuildContext context, HostModerationState lock) {
    final reason = moderationReasonLabel(context, lock.reasonCode);
    return Container(
      key: const Key('thread_locked_banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _deep,
        border: Border(bottom: BorderSide(color: _rule, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 16, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.uiCopy(
                zh: '此討論串已被板務鎖定（$reason），暫停回覆',
                en:
                    'This thread was locked by the board moderators '
                    '($reason); replies are paused',
              ),
              style: TextStyle(fontSize: 12.5, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  /// Replaces the reply composer while the thread is locked.
  Widget _lockedComposerNotice(BuildContext context, HostModerationState lock) {
    final reason = moderationReasonLabel(context, lock.reasonCode);
    return Container(
      key: const Key('thread_locked_composer'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: _deep,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 16, color: _muted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.uiCopy(
                zh: '討論串已鎖定（$reason），無法發表新貼文',
                en: 'Thread locked ($reason) — new posts are disabled',
              ),
              style: TextStyle(color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  /// Tombstone shown in place of someone else's removed post: content
  /// hidden, reason visible.
  Widget _removedPostTombstone(
    BuildContext context,
    Post post,
    HostModerationState removal,
  ) {
    final reason = moderationReasonLabel(context, removal.reasonCode);
    return Card(
      key: Key('removed_post_tombstone_${post.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.visibility_off_outlined, size: 18, color: _faint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.uiCopy(
                  zh: '此留言已被板務移除（$reason）',
                  en:
                      'This post was removed by the board moderators '
                      '($reason)',
                ),
                style: TextStyle(color: _muted, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Removal notice on the author's own post: their content stays visible
  /// (the host removed its board projection, never the local copy) and the
  /// reason is shown — constitution-mandated author visibility.
  Widget _ownPostRemovalNotice(
    BuildContext context,
    HostModerationState removal,
  ) {
    final reason = moderationReasonLabel(context, removal.reasonCode);
    return Container(
      key: Key('own_post_removal_notice_${removal.targetRef}'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _deep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.uiCopy(
          zh: '你的留言已被板務移除（$reason）。其他人看不到這則內容；你的本地副本不受影響。',
          en:
              'Your post was removed by the board moderators ($reason). '
              'Others no longer see it; your local copy is untouched.',
        ),
        style: TextStyle(fontSize: 12.5, color: _muted),
      ),
    );
  }

  String _formatDate(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } else if (difference.inDays > 0) {
      final n = difference.inDays;
      return context.uiCopy(zh: '$n 天前', en: '$n day${n > 1 ? 's' : ''} ago');
    } else if (difference.inHours > 0) {
      final n = difference.inHours;
      return context.uiCopy(zh: '$n 小時前', en: '$n hour${n > 1 ? 's' : ''} ago');
    } else if (difference.inMinutes > 0) {
      final n = difference.inMinutes;
      return context.uiCopy(
        zh: '$n 分鐘前',
        en: '$n minute${n > 1 ? 's' : ''} ago',
      );
    } else {
      return context.uiCopy(zh: '剛剛', en: 'Just now');
    }
  }
}

/// Per-post reaction footer (👍). Reuses the same drift reaction store + CRDT
/// `create/deleteReaction` ops as the feed [PostCard], but targets the
/// individual post ([TargetType.post]) rather than the whole thread. Reacting
/// requires a known local DID and an ops dispatcher; without them the bar is a
/// read-only count. The action row is intentionally a [Row] so a share / reply
/// affordance can be appended here later.
class _PostReactionBar extends StatefulWidget {
  const _PostReactionBar({
    super.key,
    required this.db,
    required this.postId,
    required this.localDid,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.dark = false,
  });

  final AppDatabase db;
  final String postId;
  final String? localDid;
  final OpsDispatchService? opsDispatchService;
  final Future<void> Function()? onFlushPendingOps;
  final bool dark;

  @override
  State<_PostReactionBar> createState() => _PostReactionBarState();
}

class _PostReactionBarState extends State<_PostReactionBar> {
  late final DriftReactionRepository _reactionRepo;
  bool _loading = true;
  bool _busy = false;
  bool _reacted = false;
  int _likeCount = 0;

  bool get _canReact =>
      widget.localDid != null && widget.opsDispatchService != null;

  @override
  void initState() {
    super.initState();
    _reactionRepo = DriftReactionRepository(widget.db);
    unawaited(_load());
  }

  Future<void> _load() async {
    final reactions = await _reactionRepo.listByTarget(
      TargetType.post.name,
      widget.postId,
    );
    final likes = reactions
        .where((r) => r.reactionType == ReactionType.thumbsUp)
        .toList();
    if (!mounted) return;
    setState(() {
      _likeCount = likes.length;
      _reacted =
          widget.localDid != null &&
          likes.any((r) => r.userId == widget.localDid);
      _loading = false;
    });
  }

  Future<void> _toggle() async {
    final localDid = widget.localDid;
    final ops = widget.opsDispatchService;
    if (localDid == null || ops == null) return;
    setState(() => _busy = true);
    try {
      if (_reacted) {
        final existing = await _reactionRepo.getByUserAndTarget(
          localDid,
          TargetType.post.name,
          widget.postId,
        );
        if (existing != null) {
          await _reactionRepo.delete(existing.id);
          await ops.signAndEnqueue(
            CrdtOpBuilder.deleteReaction(
              authorDid: localDid,
              entityId: existing.id,
              targetType: TargetType.post.name,
              targetId: widget.postId,
            ),
          );
          if (widget.onFlushPendingOps != null) {
            unawaited(widget.onFlushPendingOps!());
          }
          if (mounted) {
            setState(() {
              _reacted = false;
              _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
            });
          }
        }
      } else {
        final reaction = Reaction(
          id: const Uuid().v4(),
          userId: localDid,
          targetType: TargetType.post,
          targetId: widget.postId,
          reactionType: ReactionType.thumbsUp,
          createdAt: DateTime.now(),
        );
        await _reactionRepo.create(reaction);
        await ops.signAndEnqueue(
          CrdtOpBuilder.createReaction(
            authorDid: localDid,
            entityId: reaction.id,
            targetType: reaction.targetType.name,
            targetId: reaction.targetId,
            reactionType: reaction.reactionType.name,
          ),
        );
        if (widget.onFlushPendingOps != null) {
          unawaited(widget.onFlushPendingOps!());
        }
        if (mounted) {
          setState(() {
            _reacted = true;
            _likeCount += 1;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Threads-style heart: ember when reacted, muted otherwise.
    final heartColor = _reacted
        ? (widget.dark ? AnsibleDesign.darkEmber : AnsibleDesign.ember)
        : (widget.dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted);
    final countColor = widget.dark
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (_canReact && !_busy && !_loading) ? _toggle : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _reacted ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: heartColor,
          ),
          if (_likeCount > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$_likeCount',
              style: TextStyle(
                fontFamily: AnsibleDesign.sans,
                fontSize: 13,
                color: countColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
