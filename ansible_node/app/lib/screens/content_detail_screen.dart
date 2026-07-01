import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/app_view_timeline_client.dart';
import '../services/handle_resolver.dart';
import '../services/ops_dispatch_service.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/author_label.dart';

/// Detail view for a standalone content item (murmur/note): the full content as
/// the head, plus a comment thread. Comments are `post` ops keyed by the
/// content's entity id (`threadId == contentId`); they read back from the
/// AppView's `GET /api/v1/thread/:thread_id`. The board-less content has no
/// local board sync, so the AppView is the only comment read path.
class ContentDetailScreen extends StatefulWidget {
  const ContentDetailScreen({
    super.key,
    required this.db,
    required this.localDid,
    required this.contentId,
    required this.authorDid,
    required this.body,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.title,
    this.timeAgo,
    this.appViewBaseUrl,
    this.screenStyle = ElixScreenStyle.paper,
  });

  final AppDatabase db;
  final String localDid;
  final String contentId;
  final String authorDid;
  final String body;
  final String? title;
  final String? timeAgo;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;

  /// Defaults to the build's configured AppView; injectable for tests.
  final String? appViewBaseUrl;

  /// Follows the originating board/feed's Paper/Ink choice.
  final ElixScreenStyle screenStyle;

  @override
  State<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends State<ContentDetailScreen> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  late final DriftPostRepository _postRepo;
  late final DriftReactionRepository _reactionRepo;
  List<_Comment> _comments = const [];
  bool _loading = true;
  bool _posting = false;
  bool _reacted = false;
  bool _isReacting = false;
  int _likeCount = 0;

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
  Color get _deep => _dark ? AnsibleDesign.darkPaperDeep : AnsibleDesign.paperDeep;
  Color get _fg => _dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
  Color get _muted => _dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
  Color get _faint => _dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
  Color get _rule => _dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
  Color get _ruleSoft => _dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
  Color get _accent => _dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent;
  Color get _danger => _dark ? AnsibleDesign.darkEmber : AnsibleDesign.danger;

  String get _appViewBaseUrl =>
      widget.appViewBaseUrl ?? AppEnvironment.appViewBaseUrl;

  @override
  void initState() {
    super.initState();
    _postRepo = DriftPostRepository(widget.db);
    _reactionRepo = DriftReactionRepository(widget.db);
    _load();
    unawaited(_loadReactions());
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _loadReactions() async {
    final reactions = await _reactionRepo.listByTarget(
      TargetType.thread.name,
      widget.contentId,
    );
    var reacted = false;
    var count = 0;
    for (final r in reactions) {
      if (r.reactionType == ReactionType.thumbsUp) {
        count++;
        if (r.userId == widget.localDid) reacted = true;
      }
    }
    if (mounted) {
      setState(() {
        _likeCount = count;
        _reacted = reacted;
      });
    }
  }

  Future<void> _toggleReaction() async {
    if (_isReacting) return;
    setState(() => _isReacting = true);
    try {
      if (_reacted) {
        final existing = await _reactionRepo.getByUserAndTarget(
          widget.localDid,
          TargetType.thread.name,
          widget.contentId,
        );
        if (existing != null) {
          await _reactionRepo.delete(existing.id);
          await widget.opsDispatchService.signAndEnqueue(
            CrdtOpBuilder.deleteReaction(
              authorDid: widget.localDid,
              entityId: existing.id,
              targetType: TargetType.thread.name,
              targetId: widget.contentId,
            ),
          );
          unawaited(widget.onFlushPendingOps());
          setState(() {
            _reacted = false;
            _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
          });
        }
      } else {
        final reaction = Reaction(
          id: const Uuid().v4(),
          userId: widget.localDid,
          targetType: TargetType.thread,
          targetId: widget.contentId,
          reactionType: ReactionType.thumbsUp,
          createdAt: DateTime.now(),
        );
        await _reactionRepo.create(reaction);
        await widget.opsDispatchService.signAndEnqueue(
          CrdtOpBuilder.createReaction(
            authorDid: widget.localDid,
            entityId: reaction.id,
            targetType: reaction.targetType.name,
            targetId: reaction.targetId,
            reactionType: reaction.reactionType.name,
          ),
        );
        unawaited(widget.onFlushPendingOps());
        setState(() {
          _reacted = true;
          _likeCount += 1;
        });
      }
    } finally {
      if (mounted) setState(() => _isReacting = false);
    }
  }

  Future<void> _load() async {
    // Local-first: comments are stored as local posts keyed by the content id
    // (own comments + any synced from followed users), so they show and persist
    // regardless of the relay/AppView. The AppView is a best-effort merge for
    // remote comments not yet synced locally.
    final byId = <String, _Comment>{};
    for (final p in await _postRepo.list(threadId: widget.contentId)) {
      byId[p.id] = _Comment(
        id: p.id,
        authorDid: p.authorId,
        body: p.content,
        createdAt: p.createdAt,
      );
    }
    if (mounted) {
      setState(() {
        _comments = _sorted(byId.values);
        _loading = false;
      });
    }

    if (_appViewBaseUrl.isEmpty) return;
    try {
      final page = await AppViewTimelineClient(
        baseUrl: _appViewBaseUrl,
      ).fetchThread(threadId: widget.contentId);
      for (final i in page.items.where((i) => i.entityType == 'comment')) {
        byId.putIfAbsent(
          i.entityId,
          () => _Comment(
            id: i.entityId,
            authorDid: i.authorDid,
            body: (i.payload['content'] ?? i.payload['body'] ?? '').toString(),
            createdAt: i.createdAt,
          ),
        );
      }
      if (mounted) setState(() => _comments = _sorted(byId.values));
    } catch (_) {
      // AppView unavailable (e.g. endpoint not deployed) — local list stands.
    }
  }

  List<_Comment> _sorted(Iterable<_Comment> comments) {
    final list = comments.toList();
    // Oldest-first reads naturally as a conversation.
    list.sort((a, b) {
      final at = a.createdAt, bt = b.createdAt;
      if (at == null || bt == null) return 0;
      return at.compareTo(bt);
    });
    return list;
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      final commentId = const Uuid().v4();
      final now = DateTime.now();
      // Persist locally first (so it survives offline / a down relay), then
      // enqueue the signed comment op for sync.
      await _postRepo.create(
        Post(
          id: commentId,
          threadId: widget.contentId,
          boardId: '',
          authorId: widget.localDid,
          content: text,
          createdAt: now,
          updatedAt: now,
          lastEditAt: now,
          signatureVerified: true,
        ),
      );
      await widget.opsDispatchService.signAndEnqueue(
        CrdtOpBuilder.createComment(
          authorDid: widget.localDid,
          entityId: commentId,
          targetId: widget.contentId,
          content: text,
        ),
      );
      unawaited(widget.onFlushPendingOps());
      if (!mounted) return;
      setState(() {
        _comments = _sorted([
          ..._comments,
          _Comment(
            id: commentId,
            authorDid: widget.localDid,
            body: text,
            createdAt: now,
          ),
        ]);
        _composer.clear();
        _posting = false;
      });
    } catch (_) {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _editComment(_Comment c) async {
    final controller = TextEditingController(text: c.body);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.uiCopy(zh: '編輯留言', en: 'Edit comment')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(context.uiCopy(zh: '儲存', en: 'Save')),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == c.body) return;
    final existing = await _postRepo.getById(c.id);
    if (existing != null) {
      final now = DateTime.now();
      await _postRepo.update(
        Post(
          id: existing.id,
          threadId: existing.threadId,
          boardId: existing.boardId,
          authorId: existing.authorId,
          content: newText,
          createdAt: existing.createdAt,
          updatedAt: now,
          lastEditAt: now,
          signatureVerified: true,
        ),
      );
    }
    await widget.opsDispatchService.signAndEnqueue(
      CrdtOpBuilder.updateComment(
        authorDid: widget.localDid,
        entityId: c.id,
        newContent: newText,
      ),
    );
    unawaited(widget.onFlushPendingOps());
    await _load();
  }

  Future<void> _deleteComment(_Comment c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.uiCopy(zh: '刪除留言', en: 'Delete comment')),
        content: Text(
          context.uiCopy(zh: '確定要刪除這則留言嗎？', en: 'Delete this comment?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.uiCopy(zh: '刪除', en: 'Delete'),
              style: TextStyle(color: _danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _postRepo.delete(c.id);
    await widget.opsDispatchService.signAndEnqueue(
      CrdtOpBuilder.deleteComment(authorDid: widget.localDid, entityId: c.id),
    );
    unawaited(widget.onFlushPendingOps());
    if (mounted) {
      setState(() => _comments = _comments.where((x) => x.id != c.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElixScreenStyleScope(
      style: widget.screenStyle,
      child: AnsibleScreenScaffold(
      title: context.uiCopy(zh: '貼文', en: 'POST'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                _head(context),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    child: Text(
                      context.uiCopy(
                        zh: '還沒有留言，搶頭香！',
                        en: 'No comments yet — be the first.',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: _faint,
                      ),
                    ),
                  )
                else
                  for (final c in _comments) _commentRow(context, c),
              ],
            ),
          ),
          _composerBar(context),
        ],
      ),
      ),
    );
  }

  Widget _head(BuildContext context) {
    final title = (widget.title ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _rule, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // post-top: avatar + handle + signed byline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _detailAvatar(widget.authorDid),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthorLabel(
                      did: widget.authorDid,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.sans,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: _fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (widget.timeAgo != null) widget.timeAgo!,
                        context.uiCopy(zh: '已簽署', en: 'signed'),
                      ].join(' · '),
                      style: TextStyle(
                        fontFamily: AnsibleDesign.sans,
                        fontSize: 12,
                        color: _faint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 16.5,
                height: 1.4,
                fontWeight: FontWeight.w700,
                color: _fg,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            widget.body.isEmpty ? context.l10n.noContentYet : widget.body,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 15,
              height: 1.72,
              color: _fg,
            ),
          ),
          const SizedBox(height: 14),
          // Threads-style actions.
          Row(
            children: [
              _detailAction(
                _reacted ? Icons.favorite : Icons.favorite_border,
                count: _likeCount,
                active: _reacted,
                onTap: _toggleReaction,
              ),
              const SizedBox(width: 26),
              _detailAction(
                Icons.mode_comment_outlined,
                count: _comments.length,
                onTap: () => _composerFocus.requestFocus(),
              ),
              const SizedBox(width: 26),
              _detailAction(Icons.repeat, onTap: _share),
              const Spacer(),
              _detailAction(Icons.send_outlined, onTap: _share),
            ],
          ),
        ],
      ),
    );
  }

  void _share() {
    final text = widget.body.isNotEmpty ? widget.body : (widget.title ?? '');
    if (text.isNotEmpty) Share.share(text);
  }

  Widget _detailAvatar(String did) {
    return FutureBuilder<String?>(
      initialData: HandleResolver.shared.cached(did),
      future: HandleResolver.shared.handleFor(did),
      builder: (context, snap) {
        final h = (snap.data ?? '').replaceFirst('@', '').trim();
        final initial = h.isEmpty ? '·' : h.substring(0, 1).toUpperCase();
        return Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _bg,
            ),
          ),
        );
      },
    );
  }

  Widget _detailAction(
    IconData icon, {
    int? count,
    bool active = false,
    VoidCallback? onTap,
  }) {
    final tint = active ? _accent : _muted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: tint),
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

  Widget _commentRow(BuildContext context, _Comment c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AuthorLabel(
                  did: c.authorDid,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
              ),
              // Author can edit/delete their own comment.
              if (c.authorDid == widget.localDid)
                SizedBox(
                  height: 22,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_horiz,
                      size: 18,
                      color: _faint,
                    ),
                    onSelected: (v) {
                      if (v == 'edit') _editComment(c);
                      if (v == 'delete') _deleteComment(c);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(context.uiCopy(zh: '編輯', en: 'Edit')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          context.uiCopy(zh: '刪除', en: 'Delete'),
                          style: TextStyle(color: _danger),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            c.body,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 14.5,
              height: 1.6,
              color: _fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _rule, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _composer,
                focusNode: _composerFocus,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(fontSize: 14, color: _fg),
                decoration: InputDecoration(
                  hintText: context.uiCopy(zh: '寫留言…', en: 'Write a comment…'),
                  isDense: true,
                  filled: true,
                  fillColor: _deep.withValues(alpha: 0.45),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _posting ? null : _send,
              icon: Icon(Icons.send, size: 20, color: _fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _Comment {
  const _Comment({
    required this.id,
    required this.authorDid,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String authorDid;
  final String body;
  final DateTime? createdAt;
}
