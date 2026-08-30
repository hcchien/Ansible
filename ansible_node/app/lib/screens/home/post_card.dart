import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:share_plus/share_plus.dart';

import '../../config/app_environment.dart';
import '../../l10n/app_l10n.dart';
import '../../services/elix_content_link.dart';
import '../../services/handle_resolver.dart';
import '../../services/ops_dispatch_service.dart';
import '../../services/posting_gate.dart';
import '../../services/safety_actions.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/author_label.dart';
import '../../widgets/reaction_picker.dart';
import '../../widgets/report_dialog.dart';
import '../posts_view_screen.dart';

typedef PostShareSheet =
    Future<void> Function(String text, {Rect? sharePositionOrigin});

Future<void> _defaultPostShareSheet(String text, {Rect? sharePositionOrigin}) =>
    Share.share(text, sharePositionOrigin: sharePositionOrigin);

/// A thread's first stored post is its OP; only subsequent posts are replies.
int replyCountForPosts(Iterable<Post> posts) {
  final count = posts.length;
  return count == 0 ? 0 : count - 1;
}

class PostCardData {
  PostCardData({
    required this.thread,
    required this.category,
    required this.title,
    required this.content,
    required this.author,
    required this.board,
    required this.timeAgo,
    DateTime? sortTimestamp,
    required this.reactions,
    required this.comments,
    required this.reacted,
    this.openingPost,
    this.authorTier = 'basic',
    this.authorDisplayName,
    this.authorHandle,
    this.signatureVerified = false,
    this.openableThread = true,
    this.replyPreviews = const [],
  }) : sortTimestamp = sortTimestamp ?? thread.createdAt;

  final Thread thread;
  final String category;
  final String title;
  final String content;
  final String author;
  final String board;
  final String timeAgo;
  final DateTime sortTimestamp;
  final Map<String, int> reactions;
  final int comments;
  final bool reacted;
  final Post? openingPost;
  final String authorTier;
  final String? authorDisplayName;
  final String? authorHandle;

  /// True when the post's authoring op is signature-verified — drives the
  /// "signed" badge.
  final bool signatureVerified;

  /// Whether this card backs a real thread that can be opened. Forum posts set
  /// this true; standalone murmur/note feed items have only a synthetic thread,
  /// so tapping must NOT push an (empty) thread view — it falls back to the
  /// author. Also hides the per-thread comment chip.
  final bool openableThread;

  /// Replies that caused this thread to surface in the timeline. They stay
  /// visually attached to the opening post so a reply is never presented as a
  /// context-free top-level card. The timeline caps this list; the comment
  /// count and thread detail retain the complete conversation.
  final List<ThreadReplyPreview> replyPreviews;

  store.TargetType get reactionTargetType =>
      openableThread && openingPost != null
      ? store.TargetType.post
      : store.TargetType.thread;

  String get reactionTargetId =>
      reactionTargetType == store.TargetType.post ? openingPost!.id : thread.id;

  PostCardData copyWith({
    String? authorTier,
    List<ThreadReplyPreview>? replyPreviews,
  }) => PostCardData(
    thread: thread,
    category: category,
    title: title,
    content: content,
    author: author,
    board: board,
    timeAgo: timeAgo,
    sortTimestamp: sortTimestamp,
    reactions: reactions,
    comments: comments,
    reacted: reacted,
    openingPost: openingPost,
    authorTier: authorTier ?? this.authorTier,
    authorDisplayName: authorDisplayName,
    authorHandle: authorHandle,
    signatureVerified: signatureVerified,
    openableThread: openableThread,
    replyPreviews: replyPreviews ?? this.replyPreviews,
  );
}

class ThreadReplyPreview {
  const ThreadReplyPreview({
    required this.id,
    required this.author,
    required this.content,
    required this.timeAgo,
    this.authorDisplayName,
    this.authorHandle,
    this.signatureVerified = false,
  });

  final String id;
  final String author;
  final String content;
  final String timeAgo;
  final String? authorDisplayName;
  final String? authorHandle;
  final bool signatureVerified;
}

/// A board's chosen reading style owns its card surface. The system theme is
/// only relevant for the `system` style; otherwise a Paper feed rendered while
/// iOS is in dark appearance would pair ink text with an Ink card.
Color postCardBackgroundColor({
  required ElixScreenStyle screenStyle,
  required Brightness systemBrightness,
}) {
  final useInkSurface =
      screenStyle == ElixScreenStyle.ink ||
      (screenStyle == ElixScreenStyle.system &&
          systemBrightness == Brightness.dark);
  return useInkSurface
      ? AnsibleDesign.darkPaperWhite
      : AnsibleDesign.paperWhite;
}

/// A pushed post detail continues the source board's explicit reading style.
/// Paper/Ink are user choices and must not be replaced by the device appearance
/// when navigation creates a new route.
ElixScreenStyle postDetailScreenStyle(ElixScreenStyle sourceStyle) =>
    sourceStyle;

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.data,
    required this.db,
    required this.authorDid,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.onOpenAuthor,
    this.onOpenBoard,
    this.onOpenContent,
    this.shareSheet = _defaultPostShareSheet,
    this.safetyActions,
  });

  final AppDatabase db;
  final PostCardData data;
  final String authorDid;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;
  final void Function(String authorDid)? onOpenAuthor;
  final void Function(String boardId)? onOpenBoard;

  /// Opens the content-detail/comments view for a standalone murmur/note
  /// (an item with [PostCardData.openableThread] == false). When null, such a
  /// tap falls back to the author profile.
  final void Function(PostCardData data)? onOpenContent;
  final PostShareSheet shareSheet;
  final SafetyActions? safetyActions;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _hover = false;
  late final store.DriftReactionRepository _reactionRepo;
  bool _isReacting = false;
  bool _reacted = false;
  store.ReactionType? _selectedReaction;
  int _likeCount = 0;
  bool _hidden = false;

  SafetyActions get _safetyActions => widget.safetyActions ?? SafetyActions();

  @override
  void initState() {
    super.initState();
    _reacted = widget.data.reacted;
    _selectedReaction = _reacted ? store.ReactionType.thumbsUp : null;
    _likeCount = widget.data.reactions['👍'] ?? 0;
    _reactionRepo = store.DriftReactionRepository(widget.db);
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.thread.id != widget.data.thread.id ||
        oldWidget.data.reactions['👍'] != widget.data.reactions['👍'] ||
        oldWidget.data.reacted != widget.data.reacted) {
      _reacted = widget.data.reacted;
      _selectedReaction = _reacted ? store.ReactionType.thumbsUp : null;
      _likeCount = widget.data.reactions['👍'] ?? 0;
    }
  }

  Future<void> _toggleThumbsUp() async {
    final choice = await showReactionPicker(
      context,
      selected: _selectedReaction,
    );
    if (choice == null) return;
    final localDid = widget.authorDid;
    final targetType = widget.data.reactionTargetType;
    final targetId = widget.data.reactionTargetId;
    final existing = await _reactionRepo.getByUserAndTarget(
      localDid,
      targetType.name,
      targetId,
    );
    if (choice.remove) {
      if (existing != null) {
        await _reactionRepo.delete(existing.id);
        await widget.opsDispatchService.signAndEnqueue(
          CrdtOpBuilder.deleteReaction(
            authorDid: localDid,
            entityId: existing.id,
            targetType: targetType.name,
            targetId: targetId,
            boardId: widget.data.thread.boardId,
          ),
        );
        unawaited(widget.onFlushPendingOps());
        setState(() {
          _reacted = false;
          _selectedReaction = null;
          _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
        });
      }
    } else if (existing != null) {
      final nextType = choice.type!;
      await _reactionRepo.create(
        store.Reaction(
          id: existing.id,
          userId: existing.userId,
          targetType: existing.targetType,
          targetId: existing.targetId,
          reactionType: nextType,
          createdAt: existing.createdAt,
        ),
      );
      await widget.opsDispatchService.signAndEnqueue(
        CrdtOpBuilder.updateReaction(
          authorDid: localDid,
          entityId: existing.id,
          targetType: existing.targetType.name,
          targetId: existing.targetId,
          reactionType: nextType.name,
          boardId: widget.data.thread.boardId,
        ),
      );
      unawaited(widget.onFlushPendingOps());
      setState(() => _selectedReaction = nextType);
    } else {
      final nextType = choice.type!;
      final reaction = store.Reaction(
        id: const Uuid().v4(),
        userId: localDid,
        targetType: targetType,
        targetId: targetId,
        reactionType: nextType,
        createdAt: DateTime.now(),
      );
      await _reactionRepo.create(reaction);
      await widget.opsDispatchService.signAndEnqueue(
        CrdtOpBuilder.createReaction(
          authorDid: localDid,
          entityId: reaction.id,
          targetType: reaction.targetType.name,
          targetId: reaction.targetId,
          reactionType: reaction.reactionType.name,
          boardId: widget.data.thread.boardId,
        ),
      );
      unawaited(widget.onFlushPendingOps());
      setState(() {
        _reacted = true;
        _selectedReaction = nextType;
        _likeCount += 1;
      });
    }
  }

  void _openThread(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostsViewScreen(
          db: widget.db,
          thread: widget.data.thread,
          openingPost: widget.data.openingPost,
          authorDid: widget.authorDid,
          opsDispatchService: widget.opsDispatchService,
          onFlushPendingOps: widget.onFlushPendingOps,
          screenStyle: postDetailScreenStyle(
            ElixScreenStyleScope.styleOf(context),
          ),
        ),
      ),
    );
  }

  /// Opens the post's detail: the thread for forum posts, the content-detail
  /// (comments) view for murmur/note, else the author.
  void _openDetail() {
    if (widget.data.openableThread) {
      _openThread(context);
    } else if (widget.onOpenContent != null) {
      widget.onOpenContent!(widget.data);
    } else {
      widget.onOpenAuthor?.call(widget.data.author);
    }
  }

  Future<void> _openDesktopContextMenu(TapDownDetails details) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Text(context.uiCopy(zh: '開啟', en: 'Open')),
        ),
        PopupMenuItem(
          value: 'share',
          child: Text(context.uiCopy(zh: '分享', en: 'Share')),
        ),
        if (widget.data.author != widget.authorDid)
          PopupMenuItem(
            value: 'report',
            child: Text(context.uiCopy(zh: '檢舉', en: 'Report')),
          ),
        if (widget.data.author != widget.authorDid)
          PopupMenuItem(
            value: 'block',
            child: Text(
              context.uiCopy(zh: '封鎖並檢舉使用者', en: 'Block and report user'),
            ),
          ),
      ],
    );
    if (!mounted) return;
    if (action == 'open') _openDetail();
    if (action == 'share') await _share();
    if (action == 'report') await _reportContent();
    if (action == 'block') await _blockAndReport();
  }

  String get _safetyTargetKind =>
      widget.data.openableThread ? 'thread' : 'content';

  Future<void> _reportContent() async {
    final draft = await showReportDialog(context);
    if (draft == null || !mounted) return;
    try {
      await _safetyActions.reportContent(
        reporterDid: widget.authorDid,
        subjectDid: widget.data.author,
        targetKind: _safetyTargetKind,
        targetRef: widget.data.thread.id,
        reasonCode: draft.reasonCode,
        note: draft.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(zh: '已將檢舉送交管理者', en: 'Report sent to the operator'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '目前無法送出檢舉，請稍後再試',
              en: 'Could not send the report. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _blockAndReport() async {
    final draft = await showReportDialog(context, blockUser: true);
    if (draft == null || !mounted) return;
    var notified = true;
    try {
      await _safetyActions.blockAndReport(
        reporterDid: widget.authorDid,
        subjectDid: widget.data.author,
        targetKind: _safetyTargetKind,
        targetRef: widget.data.thread.id,
        reasonCode: draft.reasonCode,
        note: draft.note,
      );
    } catch (_) {
      notified = false;
    }
    if (!mounted) return;
    setState(() => _hidden = true);
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

  /// "↗ pass on" — share the post's text via the platform share sheet.
  Future<void> _share() async {
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    var text = widget.data.content.isNotEmpty
        ? widget.data.content
        : widget.data.title;
    if (widget.data.openableThread) {
      final projection = await DriftHostedBoardRepository(
        widget.db,
      ).getProjectionByLocalBoardId(widget.data.thread.boardId);
      final publicUrl = projection == null
          ? null
          : ElixContentLink.threadUrl(
              frontendBaseUrl: AppEnvironment.forumWebBaseUrl,
              boardId: projection.hostedBoardId,
              threadId: widget.data.thread.id,
            );
      if (publicUrl != null) text = publicUrl;
    }
    if (text.isEmpty) return;
    try {
      await widget.shareSheet(text, sharePositionOrigin: origin);
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

  /// Avatar: the author's initial (serif), amber-filled when the opening op is
  /// signed (or it's the local user) — matches the Elix feed mockup. Resolves
  /// the handle for the initial.
  Widget _avatar(ElixScreenStyleData style, bool amber) {
    return FutureBuilder<String?>(
      initialData: HandleResolver.shared.cached(widget.data.author),
      future: HandleResolver.shared.handleFor(widget.data.author),
      builder: (context, snap) {
        final h = (snap.data ?? '').replaceFirst('@', '').trim();
        final initial = h.isEmpty ? '·' : h.substring(0, 1).toUpperCase();
        return Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: amber ? style.accent : style.surface,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: amber ? style.background : style.muted,
            ),
          ),
        );
      },
    );
  }

  /// Threads-style action: an outline icon + optional count. Heart fills amber
  /// when active.
  Widget _feedAction(
    IconData icon, {
    required ElixScreenStyleData color,
    int? count,
    bool active = false,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    final tint = active
        ? (Theme.of(context).brightness == Brightness.dark
              ? AnsibleDesign.darkHighlight
              : AnsibleDesign.highlight)
        : color.muted;
    final action = GestureDetector(
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
                color: color.muted,
              ),
            ),
          ],
        ],
      ),
    );
    if (tooltip == null) return action;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(message: tooltip, child: action),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final data = widget.data;
    final thread = data.thread;
    // The board's reading style owns the whole card palette. In particular,
    // Paper must stay light even when the operating system uses dark mode.
    final screenStyle = ElixScreenStyleScope.styleOf(context);
    final style = ElixScreenStyleScope.dataOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        key: Key('post_card_${thread.id}'),
        decoration: BoxDecoration(
          color: postCardBackgroundColor(
            screenStyle: screenStyle,
            systemBrightness: Theme.of(context).brightness,
          ),
          border: Border.all(color: style.rule, width: 1),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('post_card_author_${thread.id}'),
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onOpenAuthor == null
                  ? null
                  : () => widget.onOpenAuthor!(data.author),
              child: Row(
                children: [
                  _avatar(
                    style,
                    data.signatureVerified || data.author == widget.authorDid,
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
                                did: data.author,
                                displayName: data.authorDisplayName,
                                handle: data.authorHandle,
                                style: TextStyle(
                                  fontFamily: AnsibleDesign.sans,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                  color: style.foreground,
                                ),
                              ),
                            ),
                            if (data.signatureVerified) ...[
                              const SizedBox(width: 5),
                              Icon(
                                Icons.verified,
                                size: 14,
                                color: style.accent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${data.timeAgo}'
                          '${data.signatureVerified ? context.uiCopy(zh: ' · signed', en: ' · signed') : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AnsibleDesign.sans,
                            fontSize: 12,
                            color: style.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (PostingGate.isVerifiedHuman(data.authorTier) &&
                      !data.signatureVerified) ...[
                    Icon(Icons.verified, size: 14, color: AnsibleDesign.spore),
                    const SizedBox(width: 8),
                  ],
                  if (data.author != widget.authorDid)
                    PopupMenuButton<String>(
                      key: Key('post_safety_menu_${thread.id}'),
                      tooltip: context.uiCopy(zh: '安全選項', en: 'Safety options'),
                      icon: Icon(Icons.more_horiz, color: style.muted),
                      onSelected: (value) {
                        if (value == 'open_board') {
                          widget.onOpenBoard?.call(data.thread.boardId);
                        }
                        if (value == 'report') _reportContent();
                        if (value == 'block') _blockAndReport();
                      },
                      itemBuilder: (context) => [
                        if (widget.onOpenBoard != null &&
                            data.board.trim().isNotEmpty)
                          PopupMenuItem(
                            value: 'open_board',
                            child: Text(
                              context.uiCopy(
                                zh: '前往看板 · ${data.board}',
                                en: 'Open board · ${data.board}',
                              ),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'report',
                          child: Text(context.uiCopy(zh: '檢舉', en: 'Report')),
                        ),
                        PopupMenuItem(
                          value: 'block',
                          child: Text(
                            context.uiCopy(
                              zh: '封鎖並檢舉使用者',
                              en: 'Block and report user',
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openDetail,
              onSecondaryTapDown: _openDesktopContextMenu,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.title.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 16.5,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: _hover ? style.accent : style.foreground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Transform.rotate(
                      angle: -0.035,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 56,
                        height: 6,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AnsibleDesign.darkHighlight
                            : AnsibleDesign.highlight,
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(8, -1),
                      child: Transform.rotate(
                        angle: 0.035,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 26,
                          height: 6,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AnsibleDesign.darkHighlight
                              : AnsibleDesign.highlight,
                        ),
                      ),
                    ),
                  ],
                  if (data.content.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      data.content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        color: style.foreground,
                        height: 1.72,
                        fontSize: 15,
                      ),
                    ),
                  ],
                  if (data.replyPreviews.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: style.rule, width: 2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < data.replyPreviews.length;
                            i++
                          ) ...[
                            if (i > 0) ...[
                              const SizedBox(height: 9),
                              Divider(height: 1, color: style.rule),
                              const SizedBox(height: 9),
                            ],
                            _ThreadReplyPreviewRow(
                              key: Key(
                                'thread_reply_preview_${data.replyPreviews[i].id}',
                              ),
                              reply: data.replyPreviews[i],
                              style: style,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _feedAction(
                  _reacted ? Icons.favorite : Icons.favorite_border,
                  count: _likeCount,
                  active: _reacted,
                  color: style,
                  onTap: _isReacting
                      ? null
                      : () async {
                          setState(() => _isReacting = true);
                          try {
                            await _toggleThumbsUp();
                          } finally {
                            setState(() => _isReacting = false);
                          }
                        },
                ),
                const SizedBox(width: 26),
                _feedAction(
                  Icons.mode_comment_outlined,
                  count: data.comments,
                  color: style,
                  onTap: _openDetail,
                ),
                const SizedBox(width: 26),
                _feedAction(Icons.repeat, color: style, onTap: _share),
                const Spacer(),
                _feedAction(
                  Icons.send_outlined,
                  color: style,
                  onTap: _share,
                  tooltip: context.uiCopy(zh: '分享貼文', en: 'Share post'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadReplyPreviewRow extends StatelessWidget {
  const _ThreadReplyPreviewRow({
    super.key,
    required this.reply,
    required this.style,
  });

  final ThreadReplyPreview reply;
  final ElixScreenStyleData style;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '↳',
              style: TextStyle(
                fontFamily: AnsibleDesign.sans,
                color: style.faint,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: AuthorLabel(
                did: reply.author,
                displayName: reply.authorDisplayName,
                handle: reply.authorHandle,
                style: TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  color: style.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              reply.timeAgo,
              style: TextStyle(
                fontFamily: AnsibleDesign.sans,
                color: style.faint,
                fontSize: 11.5,
              ),
            ),
            if (reply.signatureVerified) ...[
              const SizedBox(width: 5),
              Icon(Icons.verified_user_outlined, size: 12, color: style.faint),
            ],
          ],
        ),
        if (reply.content.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            reply.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              color: style.foreground,
              height: 1.55,
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }
}
