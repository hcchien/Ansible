import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_l10n.dart';
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
    setState(() {
      _posts = posts;
      _hostedProjection = projection;
      _postingBlocked = postingBlocked;
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
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
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
                                'No posts yet',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(color: AnsibleDesign.inkMuted),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Be the first to post',
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
                                                _formatDate(post.createdAt) +
                                                    (post.lastEditAt.isAfter(
                                                          post.createdAt,
                                                        )
                                                        ? ' (edited)'
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
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit),
                                                  SizedBox(width: 8),
                                                  Text('Edit'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete,
                                                    color: Colors.red,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Delete',
                                                    style: TextStyle(
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
                    child: _postingBlocked
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
