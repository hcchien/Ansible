import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:share_plus/share_plus.dart';

import '../../l10n/app_l10n.dart';
import '../../services/handle_resolver.dart';
import '../../services/ops_dispatch_service.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/author_label.dart';
import '../posts_view_screen.dart';

class PostCardData {
  PostCardData({
    required this.thread,
    required this.category,
    required this.title,
    required this.content,
    required this.author,
    required this.board,
    required this.timeAgo,
    required this.reactions,
    required this.comments,
    required this.reacted,
    this.openingPost,
    this.authorTier = 'basic',
    this.signatureVerified = false,
    this.openableThread = true,
  });

  final Thread thread;
  final String category;
  final String title;
  final String content;
  final String author;
  final String board;
  final String timeAgo;
  final Map<String, int> reactions;
  final int comments;
  final bool reacted;
  final Post? openingPost;
  final String authorTier;

  /// True when the post's authoring op is signature-verified — drives the
  /// "signed" badge.
  final bool signatureVerified;

  /// Whether this card backs a real thread that can be opened. Forum posts set
  /// this true; standalone murmur/note feed items have only a synthetic thread,
  /// so tapping must NOT push an (empty) thread view — it falls back to the
  /// author. Also hides the per-thread comment chip.
  final bool openableThread;

  PostCardData copyWith({String? authorTier}) => PostCardData(
    thread: thread,
    category: category,
    title: title,
    content: content,
    author: author,
    board: board,
    timeAgo: timeAgo,
    reactions: reactions,
    comments: comments,
    reacted: reacted,
    openingPost: openingPost,
    authorTier: authorTier ?? this.authorTier,
    signatureVerified: signatureVerified,
    openableThread: openableThread,
  );
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.data,
    required this.db,
    required this.authorDid,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    this.onOpenAuthor,
    this.onOpenContent,
  });

  final AppDatabase db;
  final PostCardData data;
  final String authorDid;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;
  final void Function(String authorDid)? onOpenAuthor;

  /// Opens the content-detail/comments view for a standalone murmur/note
  /// (an item with [PostCardData.openableThread] == false). When null, such a
  /// tap falls back to the author profile.
  final void Function(PostCardData data)? onOpenContent;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _hover = false;
  late final store.DriftReactionRepository _reactionRepo;
  bool _isReacting = false;
  bool _reacted = false;
  int _likeCount = 0;

  @override
  void initState() {
    super.initState();
    _reacted = widget.data.reacted;
    _likeCount = widget.data.reactions['👍'] ?? 0;
    _reactionRepo = store.DriftReactionRepository(widget.db);
  }

  Future<void> _toggleThumbsUp(String targetId, bool currentlyReacted) async {
    final localDid = widget.authorDid;
    if (currentlyReacted) {
      final existing = await _reactionRepo.getByUserAndTarget(
        localDid,
        store.TargetType.thread.name,
        targetId,
      );
      if (existing != null) {
        await _reactionRepo.delete(existing.id);
        await widget.opsDispatchService.signAndEnqueue(
          CrdtOpBuilder.deleteReaction(
            authorDid: localDid,
            entityId: existing.id,
            targetType: store.TargetType.thread.name,
            targetId: targetId,
          ),
        );
        unawaited(widget.onFlushPendingOps());
        setState(() {
          _reacted = false;
          _likeCount = (_likeCount - 1).clamp(0, 1 << 30);
        });
      }
    } else {
      final reaction = store.Reaction(
        id: const Uuid().v4(),
        userId: localDid,
        targetType: store.TargetType.thread,
        targetId: targetId,
        reactionType: store.ReactionType.thumbsUp,
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
        ),
      );
      unawaited(widget.onFlushPendingOps());
      setState(() {
        _reacted = true;
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
          screenStyle: ElixScreenStyleScope.styleOf(context),
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

  /// "↗ pass on" — share the post's text via the platform share sheet.
  void _share() {
    final text = widget.data.content.isNotEmpty
        ? widget.data.content
        : widget.data.title;
    if (text.isNotEmpty) Share.share(text);
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
  }) {
    final tint = active ? color.accent : color.muted;
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
                color: color.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final thread = data.thread;
    // Theme-aware: the timeline/personal boards render on a dark screen style,
    // so colours must come from the active screen style, not hardcoded ink.
    final style = ElixScreenStyleScope.dataOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _openDetail,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? AnsibleDesign.darkPaperWhite
                : AnsibleDesign.paperWhite,
            border: Border.all(color: style.rule, width: 1),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        GestureDetector(
                          onTap: widget.onOpenAuthor == null
                              ? null
                              : () => widget.onOpenAuthor!(data.author),
                          child: AuthorLabel(
                            did: data.author,
                            style: TextStyle(
                              fontFamily: AnsibleDesign.sans,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: style.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${data.timeAgo}'
                          '${data.signatureVerified ? context.uiCopy(zh: ' · 已簽署', en: ' · signed') : ''}',
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
                  if (data.authorTier == 'verified_human') ...[
                    Icon(Icons.verified, size: 14, color: AnsibleDesign.spore),
                    const SizedBox(width: 8),
                  ],
                  if (data.signatureVerified)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AnsibleDesign.spore,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
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
                              await _toggleThumbsUp(thread.id, _reacted);
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
                  _feedAction(Icons.send_outlined, color: style, onTap: _share),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
