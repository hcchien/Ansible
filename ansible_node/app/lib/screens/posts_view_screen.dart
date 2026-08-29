import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../l10n/moderation_copy.dart';
import '../l10n/user_facing_error.dart';
import '../services/elix_content_link.dart';
import '../services/forum_host_client.dart';
import '../services/board_access_presentation_service.dart';
import '../services/ops_dispatch_service.dart';
import '../services/posting_gate.dart';
import '../services/private_board_op_factory.dart';
import '../services/safety_actions.dart';
import '../services/user_presence_verifier.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import '../services/handle_resolver.dart';
import '../widgets/author_label.dart';
import '../widgets/reaction_picker.dart';
import 'post_composer_screen.dart';
import '../widgets/posting_gate_notice.dart';
import '../widgets/report_dialog.dart';
import 'user_profile_screen.dart';

/// Seam for invoking the platform share sheet. Defaults to share_plus; tests
/// inject a fake to assert the constructed URL without a real share sheet.
typedef ShareSheet =
    Future<void> Function(
      String text, {
      String? subject,
      Rect? sharePositionOrigin,
    });

Future<void> _defaultShareSheet(
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

  /// Test seams shared by the signed App rail for poll votes.
  final ForumHostClient Function(String baseUrl)? pollClientFactory;
  final Future<String> Function(List<int> payload)? pollPayloadSigner;
  final SafetyActions? safetyActions;

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
    this.pollClientFactory,
    this.pollPayloadSigner,
    this.safetyActions,
  });

  @override
  State<PostsViewScreen> createState() => _PostsViewScreenState();
}

class _PostsViewScreenState extends State<PostsViewScreen> {
  late final DriftPostRepository _postRepo;
  late final DriftThreadRepository _threadRepo;
  late Thread _thread;
  List<Post> _posts = [];
  bool _isLoading = true;
  Map<String, Object?>? _pollResult;
  String? _submittingPollOption;
  bool _pollVoteAccepted = false;

  /// Local authored ops carry the only trustworthy answer to whether the
  /// Relay accepted a post. A local signature alone must never be presented as
  /// successful publication.
  Map<String, String> _relayStatusByEntityId = const {};

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
  SafetyActions get _safetyActions => widget.safetyActions ?? SafetyActions();

  @override
  void initState() {
    super.initState();
    _postRepo = DriftPostRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _thread = widget.thread;
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    final posts = [...await _postRepo.list(threadId: widget.thread.id)];
    final queuedOps = await DriftOpsQueueRepository(
      widget.db,
    ).listAll(limit: 1000);
    final relayStatusByEntityId = <String, String>{
      for (final op in queuedOps)
        if (op.authorDid == _authorDid &&
            (op.entityType == 'thread' || op.entityType == 'post'))
          op.entityId: op.status,
    };
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
    final blockedAuthors = await _safetyActions.blockedAuthors(_authorDid);
    posts.removeWhere(
      (post) =>
          post.authorId != _authorDid && blockedAuthors.contains(post.authorId),
    );
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
      _relayStatusByEntityId = relayStatusByEntityId;
      _board = board;
      _hostedProjection = projection;
      _postingBlocked = postingBlocked;
      _threadLock = threadLock;
      _removedByPostId = removedByPostId;
      _remoteRemoval = remoteRemoval;
      _isLoading = false;
    });
    // Tally data is a public Forum Host projection, separate from the signed
    // poll definition. Refresh it whenever a poll detail is opened; the
    // persisted snapshot keeps the detail useful offline meanwhile.
    if (projection != null && _thread.poll != null) {
      unawaited(_refreshPollResult(projection));
    }
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
      frontendBaseUrl: AppEnvironment.forumWebBaseUrl,
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
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await widget.shareSheet(
        url,
        subject: widget.thread.title,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '無法開啟分享面板，請稍後再試。',
              en: 'Could not open the share sheet. Please try again.',
            ),
          ),
        ),
      );
    }
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
        utf8.encode(forumHostCanonicalJson(canonicalPayload)),
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

  Future<void> _blockAndReportAuthor({Post? post}) async {
    final subjectDid = post?.authorId ?? widget.thread.authorId;
    if (subjectDid.isEmpty || subjectDid == _authorDid) return;
    final draft = await showReportDialog(context, blockUser: true);
    if (draft == null || !mounted) return;

    var notified = true;
    try {
      await _safetyActions.blockAndReport(
        reporterDid: _authorDid,
        subjectDid: subjectDid,
        targetKind: post == null ? 'thread' : 'post',
        targetRef: post?.id ?? widget.thread.id,
        reasonCode: draft.reasonCode,
        note: draft.note,
      );
    } catch (_) {
      notified = false;
    }
    if (!mounted) return;
    if (post == null || widget.thread.authorId == subjectDid) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _posts = _posts.where((item) => item.authorId != subjectDid).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notified
              ? context.uiCopy(
                  zh: '已封鎖；內容已移除並通知管理者',
                  en: 'User blocked; content removed and operator notified',
                )
              : context.uiCopy(
                  zh: '已封鎖並移除內容；管理者通知暫時送出失敗',
                  en: 'User blocked and content removed; operator notification failed',
                ),
        ),
      ),
    );
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
      final projection = _hostedProjection;
      await _enqueueAndFlush(
        projection?.contentVisibility == 'end_to_end_encrypted'
            ? await PrivateBoardOpFactory().createPost(
                board: projection!,
                authorDid: _authorDid,
                entityId: post.id,
                threadId: post.threadId,
                content: post.content,
                parentPostId: post.parentPostId,
                createdAt: now,
              )
            : CrdtOpBuilder.createPost(
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

  Future<void> _editOpeningPost(Post post) async {
    final titleController = TextEditingController(text: _thread.title);
    final bodyController = TextEditingController(text: post.content);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.uiCopy(zh: '編輯貼文', en: 'Edit post')),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('edit_thread_title_field'),
                controller: titleController,
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: '標題', en: 'Title'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('edit_thread_body_field'),
                controller: bodyController,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: '內容', en: 'Content'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              final body = bodyController.text.trim();
              if (title.isEmpty || body.isEmpty) return;
              Navigator.pop(dialogContext, (title, body));
            },
            child: Text(context.uiCopy(zh: '儲存', en: 'Save')),
          ),
        ],
      ),
    );
    titleController.dispose();
    bodyController.dispose();
    if (result == null) return;

    final now = DateTime.now();
    final (title, body) = result;
    final titleChanged = title != _thread.title;
    final bodyChanged = body != post.content;
    if (!titleChanged && !bodyChanged) return;

    if (titleChanged) {
      final updatedThread = Thread(
        id: _thread.id,
        boardId: _thread.boardId,
        title: title,
        authorId: _thread.authorId,
        createdAt: _thread.createdAt,
        updatedAt: now,
        isDeleted: _thread.isDeleted,
      );
      await _threadRepo.update(updatedThread);
      await _enqueueAndFlush(
        CrdtOpBuilder.updateThread(
          authorDid: _authorDid,
          entityId: updatedThread.id,
          newTitle: title,
        ),
      );
      if (mounted) setState(() => _thread = updatedThread);
    }

    if (bodyChanged && !post.id.endsWith(':legacy-opening')) {
      final updatedPost = Post(
        id: post.id,
        threadId: post.threadId,
        boardId: post.boardId,
        authorId: post.authorId,
        content: body,
        createdAt: post.createdAt,
        updatedAt: now,
        lastEditAt: now,
        parentPostId: post.parentPostId,
        isDeleted: post.isDeleted,
        signatureVerified: true,
      );
      await _postRepo.update(updatedPost);
      await _enqueueAndFlush(
        CrdtOpBuilder.updatePost(
          authorDid: _authorDid,
          entityId: updatedPost.id,
          newContent: body,
        ),
      );
    }
    await _loadPosts();
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

  Future<void> _deleteOpeningPost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.uiCopy(zh: '刪除貼文', en: 'Delete post')),
        content: Text(
          context.uiCopy(
            zh: '這會刪除整則貼文與討論串。已同步的裝置會收到刪除標記，確定繼續嗎？',
            en: 'This deletes the post and its thread. Synced devices will receive a tombstone. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.uiCopy(zh: '刪除', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _threadRepo.delete(_thread.id);
    if (!post.id.endsWith(':legacy-opening')) {
      await _postRepo.delete(post.id);
      await _enqueueAndFlush(
        CrdtOpBuilder.deletePost(authorDid: _authorDid, entityId: post.id),
      );
    }
    await _enqueueAndFlush(
      CrdtOpBuilder.deleteThread(authorDid: _authorDid, entityId: _thread.id),
    );
    if (mounted) Navigator.of(context).pop(true);
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
          if (widget.thread.authorId != _authorDid)
            IconButton(
              key: const Key('block_thread_author_button'),
              icon: const Icon(Icons.block, size: 21),
              tooltip: context.uiCopy(
                zh: '封鎖並檢舉作者',
                en: 'Block and report author',
              ),
              onPressed: _blockAndReportAuthor,
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
              Expanded(
                child: InkWell(
                  key: Key('open_author_profile_${post.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openAuthorProfile(post.authorId),
                  child: Row(
                    children: [
                      _avatar(
                        post.authorId,
                        size: 40,
                        signed: post.signatureVerified,
                      ),
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
                                  Icon(
                                    Icons.verified,
                                    size: 14,
                                    color: _accent,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            _opSub(context, post, edited),
                          ],
                        ),
                      ),
                    ],
                  ),
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
            _thread.title,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 22,
              height: 1.4,
              fontWeight: FontWeight.w500,
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
          if ((_pollResult ?? _thread.pollResults ?? _thread.poll)
              case final poll?) ...[
            const SizedBox(height: 16),
            _pollDetail(context, poll),
          ],
          if (removal == null) ...[
            const SizedBox(height: 6),
            _opActions(context, post),
          ],
        ],
      ),
    );
  }

  Widget _pollDetail(BuildContext context, Map<String, Object?> poll) {
    final options =
        (poll['options'] as List?)
            ?.whereType<Map>()
            .map(
              (option) => (
                id: option['id']?.toString() ?? '',
                label: option['label']?.toString() ?? '',
                votes: int.tryParse(option['votes']?.toString() ?? '') ?? 0,
              ),
            )
            .where((option) => option.id.isNotEmpty && option.label.isNotEmpty)
            .toList() ??
        const <({String id, String label, int votes})>[];
    final closesAt = DateTime.tryParse(poll['closes_at']?.toString() ?? '');
    final closed = closesAt != null && !closesAt.isAfter(DateTime.now());
    final totalVotes = options.fold<int>(
      0,
      (sum, option) => sum + option.votes,
    );
    return Container(
      key: const Key('thread_poll_detail'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        border: Border.all(color: _rule, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.poll_outlined, size: 18, color: _accent),
              const SizedBox(width: 8),
              Text(
                closed
                    ? context.uiCopy(zh: '已結束', en: 'CLOSED')
                    : context.uiCopy(zh: '投票中', en: 'LIVE POLL'),
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                  letterSpacing: 1,
                  color: closed ? _faint : _accent,
                ),
              ),
              const Spacer(),
              if (closesAt != null)
                Text(
                  _formatDate(context, closesAt),
                  style: TextStyle(fontSize: 12, color: _faint),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.uiCopy(
              zh: '僅具本版發言資格者可投票；每人一票。',
              en: 'One vote per eligible board speaker.',
            ),
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 10),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: _deep,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key('poll_option_${option.id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap:
                      closed ||
                          _pollVoteAccepted ||
                          _submittingPollOption != null
                      ? null
                      : () => _castPollVote(option.id),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: _rule, width: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(color: _fg),
                          ),
                        ),
                        if (_submittingPollOption == option.id)
                          const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (totalVotes > 0)
                          Text(
                            '${((option.votes / totalVotes) * 100).round()}%',
                            style: TextStyle(color: _muted),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Text(
            _pollVoteAccepted
                ? context.uiCopy(zh: '已完成投票', en: 'Your vote was submitted')
                : totalVotes > 0
                ? context.uiCopy(zh: '$totalVotes 人投票', en: '$totalVotes votes')
                : context.uiCopy(
                    zh: '選擇一個選項即可投票',
                    en: 'Choose one option to vote',
                  ),
            style: TextStyle(fontSize: 12, color: _faint),
          ),
        ],
      ),
    );
  }

  Future<void> _castPollVote(String optionId) async {
    final projection = _hostedProjection;
    if (projection == null) {
      _showPollError('poll_not_hosted');
      return;
    }
    final host = await DriftRemoteNodeRepository(
      widget.db,
    ).getById(projection.forumHostId);
    if (host == null || !mounted) {
      _showPollError('forum_host_unavailable');
      return;
    }
    setState(() => _submittingPollOption = optionId);
    final createdAt = DateTime.now().toUtc();
    final intentId = const Uuid().v4();
    final payload = CastPollVoteIntent.canonicalPayload(
      intentId: intentId,
      authorDid: _authorDid,
      targetForumHost: host.url,
      boardId: projection.hostedBoardId,
      pollId: _thread.id,
      optionId: optionId,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    final client =
        (widget.pollClientFactory ??
        widget.reportClientFactory ??
        (baseUrl) => ForumHostClient(baseUrl: baseUrl))(host.url);
    HardwareAuthenticationSession? authenticationSession;
    try {
      final authenticationReason = context.uiCopy(
        zh: '請驗證裝置持有人，以送出這次投票。',
        en: 'Authenticate to submit this vote.',
      );
      authenticationSession = await HardwareAuthenticationSession.begin(
        localizedReason: authenticationReason,
      );
      if (authenticationSession == null) {
        final authenticated = await LocalDeviceUserPresenceVerifier().verify(
          reason: authenticationReason,
        );
        if (!authenticated) throw StateError('device_auth_cancelled');
      }
      final reuseAuthenticationContext = authenticationSession != null;
      final didSigner = DidSignerImpl(
        reuseAuthenticationContext: reuseAuthenticationContext,
      );
      final proofHeaders = await _pollProofHeaders(
        projection: projection,
        hostUrl: host.url,
        didSigner: didSigner,
        reuseAuthenticationContext: reuseAuthenticationContext,
      );
      final signature =
          await (widget.pollPayloadSigner ??
              widget.reportPayloadSigner ??
              (bytes) => didSigner.sign(bytes).then((value) => value.hex))(
            utf8.encode(forumHostCanonicalJson(payload)),
          );
      final response = await client.castPollVote(
        CastPollVoteIntent(
          intentId: intentId,
          authorDid: _authorDid,
          targetForumHost: host.url,
          boardId: projection.hostedBoardId,
          pollId: _thread.id,
          optionId: optionId,
          createdAt: createdAt,
          expiresAt: createdAt.add(const Duration(minutes: 5)),
          signature: signature,
        ),
        headers: proofHeaders,
      );
      final result = _mergedPollResult(response['poll']);
      if (result == null) throw const FormatException('Missing poll result');
      await _persistPollResult(result);
      if (!mounted) return;
      setState(() => _pollVoteAccepted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.uiCopy(zh: '投票成功', en: 'Vote submitted')),
        ),
      );
    } on BoardAccessException catch (error) {
      if (mounted) _showPollError(error.code);
    } on ForumHostException catch (error) {
      if (mounted) _showPollError(error.error ?? 'invalid_poll_vote');
    } on StateError catch (error) {
      if (mounted) _showPollError(error.message.toString());
    } catch (_) {
      if (mounted) _showPollError('forum_host_unavailable');
    } finally {
      await authenticationSession?.close();
      client.close();
      if (mounted) setState(() => _submittingPollOption = null);
    }
  }

  bool _requiresPollCapability(HostedBoardProjection projection) {
    final post = projection.accessPolicy['post'];
    final requirement = post is Map ? post['requirement'] : null;
    return requirement is String &&
        requirement != 'public' &&
        requirement != 'posting_policy';
  }

  Future<Map<String, String>> _pollProofHeaders({
    required HostedBoardProjection projection,
    required String hostUrl,
    required DidSigner didSigner,
    required bool reuseAuthenticationContext,
  }) async {
    if (!_requiresPollCapability(projection)) return const {};
    final endpoint = Uri.parse(hostUrl).resolve(
      '/api/v1/forum-host/boards/${Uri.encodeComponent(projection.hostedBoardId)}/polls/${Uri.encodeComponent(_thread.id)}/votes',
    );
    final access = BoardAccessPresentationService(
      walletRepository: DriftWalletRepository(widget.db),
      didSigner: didSigner,
    );
    final capability = await access.authorize(
      forumHost: Uri.parse(hostUrl),
      boardId: projection.hostedBoardId,
      action: 'post',
      reuseAuthenticationContext: reuseAuthenticationContext,
    );
    return access.proofHeaders(
      capability: capability,
      method: 'POST',
      requestUri: endpoint,
      scope: 'post',
      reuseAuthenticationContext: reuseAuthenticationContext,
    );
  }

  Map<String, Object?>? _mergedPollResult(Object? raw) {
    if (raw is! Map) return null;
    final result = Thread.parsePollResults(raw);
    if (result == null) return null;
    // Retain the signed closing time when the host response omits it.
    return {...?_thread.poll, ...result};
  }

  Future<void> _refreshPollResult(HostedBoardProjection projection) async {
    final host = await DriftRemoteNodeRepository(
      widget.db,
    ).getById(projection.forumHostId);
    if (host == null) return;
    final client =
        (widget.pollClientFactory ??
        widget.reportClientFactory ??
        (baseUrl) => ForumHostClient(baseUrl: baseUrl))(host.url);
    try {
      final response = await client.fetchPoll(
        projection.hostedBoardId,
        _thread.id,
      );
      final result = _mergedPollResult(response['poll']);
      if (result != null) await _persistPollResult(result);
    } on ForumHostException {
      // A cached public snapshot remains valid offline or when the poll has
      // not reached this host yet; voting retains its own reason-coded errors.
    } on FormatException {
      // Ignore malformed public snapshots rather than replacing the signed
      // local poll definition.
    } finally {
      client.close();
    }
  }

  Future<void> _persistPollResult(Map<String, Object?> result) async {
    final updated = Thread(
      id: _thread.id,
      boardId: _thread.boardId,
      title: _thread.title,
      authorId: _thread.authorId,
      poll: _thread.poll,
      pollResults: result,
      createdAt: _thread.createdAt,
      // A tally refresh is not a signed content edit, so it must not change
      // thread ordering or publication timestamps.
      updatedAt: _thread.updatedAt,
      isDeleted: _thread.isDeleted,
    );
    await _threadRepo.update(updated);
    if (!mounted) return;
    setState(() {
      _thread = updated;
      _pollResult = result;
    });
  }

  void _showPollError(String code) {
    final message = switch (code) {
      'already_voted' => context.uiCopy(
        zh: '你已經投過票了',
        en: 'You have already voted',
      ),
      'poll_closed' => context.uiCopy(zh: '投票已結束', en: 'This poll is closed'),
      'posting_requires_tier' ||
      'board_capability_required' ||
      'credential_not_authorized' => context.uiCopy(
        zh: '你目前不具備本版投票資格',
        en: 'You are not eligible to vote on this board',
      ),
      'device_auth_cancelled' => context.uiCopy(
        zh: '未完成裝置驗證，投票未送出',
        en: 'Device authentication was not completed; the vote was not sent',
      ),
      _ => context.uiCopy(
        zh: '目前無法送出投票，請稍後再試',
        en: 'Could not submit the vote. Try again later',
      ),
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
          if (_publicationLabel(context, post) case final publication?) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: publication.$1,
              style: TextStyle(color: publication.$2),
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

  /// Returns a user-facing publication state derived from the Relay queue, not
  /// merely from local signing. Remote authors have already passed Relay's
  /// verification boundary before they reach this local projection.
  (String, Color)? _publicationLabel(BuildContext context, Post post) {
    if (post.authorId != _authorDid) {
      return post.signatureVerified
          ? (context.uiCopy(zh: 'Relay 已驗證', en: 'Relay verified'), _accent)
          : null;
    }

    switch (_relayStatusByEntityId[post.id]) {
      case 'synced':
        return (
          context.uiCopy(zh: '已上傳 Relay', en: 'Uploaded to Relay'),
          _accent,
        );
      case 'pending':
      case 'sent':
        return (
          context.uiCopy(zh: '待上傳 Relay', en: 'Waiting for Relay'),
          _muted,
        );
      case 'blocked':
      case 'rejected':
        return (
          context.uiCopy(zh: 'Relay 同步失敗', en: 'Relay sync failed'),
          AnsibleDesign.danger,
        );
      default:
        return post.signatureVerified
            ? (context.uiCopy(zh: '僅本機已簽署', en: 'Signed locally only'), _muted)
            : null;
    }
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
          boardId: widget.thread.boardId,
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
        _actionIcon(
          Icons.ios_share,
          key: const Key('share_thread_action'),
          onTap: _shareThread,
        ),
      ],
    );
  }

  Widget _actionIcon(
    IconData icon, {
    Key? key,
    int? count,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: key,
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
          Expanded(
            child: InkWell(
              key: Key('open_author_profile_${post.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openAuthorProfile(post.authorId),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatar(
                    post.authorId,
                    size: 34,
                    signed: post.signatureVerified,
                  ),
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
                                      ? context.uiCopy(
                                          zh: '（已編輯）',
                                          en: ' (edited)',
                                        )
                                      : ''),
                              style: TextStyle(
                                fontFamily: AnsibleDesign.sans,
                                fontSize: 12,
                                color: _faint,
                              ),
                            ),
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
                            boardId: widget.thread.boardId,
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
            ),
          ),
          _postMenu(context, post),
        ],
      ),
    );
  }

  void _openAuthorProfile(String authorDid) {
    if (authorDid.isEmpty || authorDid == _authorDid) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          db: widget.db,
          followerDid: _authorDid,
          did: authorDid,
        ),
      ),
    );
  }

  /// Per-post overflow menu (edit / delete / report).
  Widget _postMenu(BuildContext context, Post post) {
    final isOpeningPost = _posts.isNotEmpty && _posts.first.id == post.id;
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
          if (post.authorId != _authorDid)
            PopupMenuItem(
              value: 'block',
              child: Text(
                context.uiCopy(zh: '封鎖並檢舉使用者', en: 'Block and report user'),
              ),
            ),
        ],
        onSelected: (value) {
          if (value == 'edit') {
            if (isOpeningPost) {
              _editOpeningPost(post);
            } else {
              _editPost(post);
            }
          } else if (value == 'delete') {
            if (isOpeningPost) {
              _deleteOpeningPost(post);
            } else {
              _deletePost(post);
            }
          } else if (value == 'report') {
            _reportContent(post: post);
          } else if (value == 'block') {
            _blockAndReportAuthor(post: post);
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
        border: Border(top: BorderSide(color: _ruleSoft, width: 0.5)),
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
                          border: Border.all(color: _rule, width: 0.5),
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
    required this.boardId,
    required this.localDid,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.dark = false,
  });

  final AppDatabase db;
  final String postId;
  final String boardId;
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
  ReactionType? _selectedReaction;
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
    if (!mounted) return;
    setState(() {
      _likeCount = reactions.map((reaction) => reaction.userId).toSet().length;
      final mine = widget.localDid == null
          ? null
          : reactions.where((r) => r.userId == widget.localDid).firstOrNull;
      _reacted = mine != null;
      _selectedReaction = mine?.reactionType;
      _loading = false;
    });
  }

  Future<void> _toggle() async {
    final localDid = widget.localDid;
    final ops = widget.opsDispatchService;
    if (localDid == null || ops == null) return;
    final choice = await showReactionPicker(
      context,
      selected: _selectedReaction,
    );
    if (choice == null) return;
    setState(() => _busy = true);
    try {
      final existing = await _reactionRepo.getByUserAndTarget(
        localDid,
        TargetType.post.name,
        widget.postId,
      );
      if (choice.remove) {
        if (existing != null) {
          await _reactionRepo.delete(existing.id);
          await ops.signAndEnqueue(
            CrdtOpBuilder.deleteReaction(
              authorDid: localDid,
              entityId: existing.id,
              targetType: TargetType.post.name,
              targetId: widget.postId,
              boardId: widget.boardId,
            ),
          );
          if (widget.onFlushPendingOps != null) {
            unawaited(widget.onFlushPendingOps!());
          }
          if (mounted) {
            setState(() {
              _reacted = false;
              _selectedReaction = null;
              _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
            });
          }
        }
      } else if (existing != null) {
        final next = choice.type!;
        await _reactionRepo.create(
          Reaction(
            id: existing.id,
            userId: existing.userId,
            targetType: existing.targetType,
            targetId: existing.targetId,
            reactionType: next,
            createdAt: existing.createdAt,
          ),
        );
        await ops.signAndEnqueue(
          CrdtOpBuilder.updateReaction(
            authorDid: localDid,
            entityId: existing.id,
            targetType: existing.targetType.name,
            targetId: existing.targetId,
            reactionType: next.name,
            boardId: widget.boardId,
          ),
        );
        if (widget.onFlushPendingOps != null) {
          unawaited(widget.onFlushPendingOps!());
        }
        if (mounted) setState(() => _selectedReaction = next);
      } else {
        final next = choice.type!;
        final reaction = Reaction(
          id: const Uuid().v4(),
          userId: localDid,
          targetType: TargetType.post,
          targetId: widget.postId,
          reactionType: next,
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
            boardId: widget.boardId,
          ),
        );
        if (widget.onFlushPendingOps != null) {
          unawaited(widget.onFlushPendingOps!());
        }
        if (mounted) {
          setState(() {
            _reacted = true;
            _selectedReaction = next;
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
