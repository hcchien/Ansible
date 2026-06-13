import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_l10n.dart';
import '../l10n/moderation_copy.dart';
import '../l10n/user_facing_error.dart';
import '../services/forum_host_client.dart';
import '../services/ops_dispatch_service.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';
import '../widgets/post_form_dialog.dart';
import '../widgets/posting_gate_notice.dart';
import '../widgets/report_dialog.dart';

class PostsViewScreen extends StatefulWidget {
  final AppDatabase db;
  final Thread thread;
  final String? authorDid;
  final OpsDispatchService? opsDispatchService;
  final Future<void> Function()? onFlushPendingOps;

  const PostsViewScreen({
    super.key,
    required this.db,
    required this.thread,
    this.authorDid,
    this.opsDispatchService,
    this.onFlushPendingOps,
  });

  @override
  State<PostsViewScreen> createState() => _PostsViewScreenState();
}

class _PostsViewScreenState extends State<PostsViewScreen> {
  late final DriftPostRepository _postRepo;
  List<Post> _posts = [];
  bool _isLoading = true;

  /// True when the board requires a higher tier than the local user has.
  /// Client-side UX only — the relay re-checks at intent acceptance.
  bool _postingBlocked = false;

  /// Set when this thread's board is hosted by a Forum Host; reporting is
  /// only possible for hosted content (local-only boards have no moderator).
  HostedBoardProjection? _hostedProjection;

  /// Host moderation overlay (synced snapshot): the lock entry for this
  /// thread, if any, and removal entries keyed by post id. Host-scoped
  /// projection only — local content rows are never touched.
  HostModerationState? _threadLock;
  Map<String, HostModerationState> _removedByPostId = const {};

  String get _authorDid => widget.authorDid ?? widget.thread.authorId;

  @override
  void initState() {
    super.initState();
    _postRepo = DriftPostRepository(widget.db);
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    final posts = await _postRepo.list(threadId: widget.thread.id);
    final projection = await DriftHostedBoardRepository(
      widget.db,
    ).getProjectionByLocalBoardId(widget.thread.boardId);
    final postingBlocked = await _checkPostingGate(projection);
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
      _hostedProjection = projection;
      _postingBlocked = postingBlocked;
      _threadLock = threadLock;
      _removedByPostId = removedByPostId;
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
      final signature = await DidSignerImpl()
          .sign(utf8.encode(jsonEncode(canonicalPayload)))
          .then((signature) => signature.hex);
      final client = ForumHostClient(baseUrl: host.url);
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

  Future<void> _createPost() async {
    final content = await showDialog<String>(
      context: context,
      builder: (context) => const PostFormDialog(),
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
    final content = await showDialog<String>(
      context: context,
      builder: (context) => PostFormDialog(initialContent: post.content),
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
      appBar: AppBar(
        title: Text(widget.thread.title),
        backgroundColor: AnsibleDesign.paper,
        foregroundColor: AnsibleDesign.ink,
        actions: [
          if (_hostedProjection != null &&
              widget.thread.authorId != _authorDid)
            IconButton(
              key: const Key('report_thread_button'),
              icon: const Icon(Icons.outlined_flag, size: 21),
              tooltip: context.uiCopy(zh: '檢舉討論串', en: 'Report thread'),
              onPressed: () => _reportContent(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_threadLock != null)
                  _threadLockedBanner(context, _threadLock!),
                Expanded(
                  child: _posts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.message_outlined,
                                size: 64,
                                color: AnsibleDesign.inkFaint,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.uiCopy(zh: '還沒有貼文', en: 'No posts yet'),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(color: AnsibleDesign.inkMuted),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.uiCopy(
                                  zh: '搶先發表第一則貼文',
                                  en: 'Be the first to post',
                                ),
                                style: const TextStyle(
                                  color: AnsibleDesign.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            final post = _posts[index];
                            final removal = _removedByPostId[post.id];
                            // Removed on the host: others see a reason-coded
                            // tombstone; the author keeps their content and
                            // sees why (constitution Base Rule 6 — the local
                            // copy is never deleted).
                            if (removal != null &&
                                post.authorId != _authorDid) {
                              return _removedPostTombstone(
                                context,
                                post,
                                removal,
                              );
                            }
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor:
                                              AnsibleDesign.paperDeep,
                                          foregroundColor:
                                              AnsibleDesign.inkMuted,
                                          child: Text(
                                            post.authorId
                                                .substring(0, 1)
                                                .toUpperCase(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                post.authorId,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              Text(
                                                _formatDate(
                                                      context,
                                                      post.createdAt,
                                                    ) +
                                                    (post.lastEditAt.isAfter(
                                                          post.createdAt,
                                                        )
                                                        ? context.uiCopy(
                                                            zh: '（已編輯）',
                                                            en: ' (edited)',
                                                          )
                                                        : ''),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton(
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.edit),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    context.uiCopy(
                                                      zh: '編輯',
                                                      en: 'Edit',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.delete,
                                                    color: Colors.red,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    context.uiCopy(
                                                      zh: '刪除',
                                                      en: 'Delete',
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (_hostedProjection != null &&
                                                post.authorId != _authorDid)
                                              PopupMenuItem(
                                                value: 'report',
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.outlined_flag,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      context.uiCopy(
                                                        zh: '檢舉',
                                                        en: 'Report',
                                                      ),
                                                    ),
                                                  ],
                                                ),
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
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (removal != null) ...[
                                      _ownPostRemovalNotice(context, removal),
                                      const SizedBox(height: 12),
                                    ],
                                    Text(post.content),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: AnsibleDesign.paper,
                    border: Border(
                      top: BorderSide(color: AnsibleDesign.rule, width: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    // A host lock wins over the tier gate: no reply UI at
                    // all while the thread is locked.
                    child: _threadLock != null
                        ? _lockedComposerNotice(context, _threadLock!)
                        : _postingBlocked
                        ? PostingGateNotice(
                            localDid: _authorDid,
                            onUpgradeCompleted: _loadPosts,
                          )
                        : ElevatedButton.icon(
                            onPressed: _createPost,
                            icon: const Icon(Icons.add),
                            label: Text(
                              context.uiCopy(zh: '發表貼文', en: 'New Post'),
                            ),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                  ),
                ),
              ],
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
      decoration: const BoxDecoration(
        color: AnsibleDesign.paperDeep,
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.rule, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AnsibleDesign.inkMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.uiCopy(
                zh: '此討論串已被板務鎖定（$reason），暫停回覆',
                en: 'This thread was locked by the board moderators '
                    '($reason); replies are paused',
              ),
              style: const TextStyle(
                fontSize: 12.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Replaces the reply composer while the thread is locked.
  Widget _lockedComposerNotice(
    BuildContext context,
    HostModerationState lock,
  ) {
    final reason = moderationReasonLabel(context, lock.reasonCode);
    return Container(
      key: const Key('thread_locked_composer'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperDeep,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 16,
            color: AnsibleDesign.inkMuted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.uiCopy(
                zh: '討論串已鎖定（$reason），無法發表新貼文',
                en: 'Thread locked ($reason) — new posts are disabled',
              ),
              style: const TextStyle(color: AnsibleDesign.inkMuted),
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
            const Icon(
              Icons.visibility_off_outlined,
              size: 18,
              color: AnsibleDesign.inkFaint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.uiCopy(
                  zh: '此留言已被板務移除（$reason）',
                  en: 'This post was removed by the board moderators '
                      '($reason)',
                ),
                style: const TextStyle(
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
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
        color: AnsibleDesign.paperDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.uiCopy(
          zh: '你的留言已被板務移除（$reason）。其他人看不到這則內容；你的本地副本不受影響。',
          en: 'Your post was removed by the board moderators ($reason). '
              'Others no longer see it; your local copy is untouched.',
        ),
        style: const TextStyle(fontSize: 12.5, color: AnsibleDesign.inkMuted),
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
      return context.uiCopy(
        zh: '$n 天前',
        en: '$n day${n > 1 ? 's' : ''} ago',
      );
    } else if (difference.inHours > 0) {
      final n = difference.inHours;
      return context.uiCopy(
        zh: '$n 小時前',
        en: '$n hour${n > 1 ? 's' : ''} ago',
      );
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
