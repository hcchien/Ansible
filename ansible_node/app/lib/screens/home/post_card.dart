import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../l10n/app_l10n.dart';
import '../../services/ops_dispatch_service.dart';
import '../../theme/ansible_design.dart';
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
    this.authorTier = 'basic',
    this.signatureVerified = false,
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
  final String authorTier;

  /// True when the post's authoring op is signature-verified — drives the
  /// "signed" badge.
  final bool signatureVerified;

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
    authorTier: authorTier ?? this.authorTier,
    signatureVerified: signatureVerified,
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
  });

  final AppDatabase db;
  final PostCardData data;
  final String authorDid;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;
  final void Function(String authorDid)? onOpenAuthor;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _hover = false;
  static const _accent = AnsibleDesign.accent;
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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final thread = data.thread;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PostsViewScreen(
                db: widget.db,
                thread: thread,
                authorDid: widget.authorDid,
                opsDispatchService: widget.opsDispatchService,
                onFlushPendingOps: widget.onFlushPendingOps,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: AnsibleDesign.paperElev,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AnsibleDesign.paperDeep,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      data.category,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.more_horiz),
                    color: AnsibleDesign.inkMuted,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                data.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _hover ? _accent : AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.content.isEmpty ? context.l10n.noContentYet : data.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AnsibleDesign.inkMuted,
                  height: 1.5,
                  fontSize: AnsibleDesign.previewTextSize,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onOpenAuthor == null
                        ? null
                        : () => widget.onOpenAuthor!(data.author),
                    child: AuthorLabel(
                      did: data.author,
                      style: const TextStyle(color: AnsibleDesign.inkMuted),
                    ),
                  ),
                  if (data.signatureVerified) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: context.uiCopy(
                        zh: '簽章已驗證',
                        en: 'Signature verified',
                      ),
                      child: const Icon(
                        Icons.verified_user,
                        size: 13,
                        color: AnsibleDesign.spore,
                      ),
                    ),
                  ],
                  if (data.authorTier == 'verified_human') ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 14, color: _accent),
                  ],
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.forum_outlined,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.board,
                    style: const TextStyle(color: AnsibleDesign.inkMuted),
                  ),
                  const SizedBox(width: 12),
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.timeAgo,
                    style: const TextStyle(color: AnsibleDesign.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _ReactionChip(
                      label: '👍',
                      count: _likeCount,
                      active: _reacted,
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
                  ),
                  _CommentChip(
                    count: data.comments,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PostsViewScreen(db: widget.db, thread: thread),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.label,
    required this.count,
    this.active = false,
    this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: active ? AnsibleDesign.paper : AnsibleDesign.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: active ? AnsibleDesign.ink : AnsibleDesign.paperDeep,
        shape: const StadiumBorder(),
      ),
      child: Text('$label $count'),
    );
  }
}

class _CommentChip extends StatelessWidget {
  const _CommentChip({required this.count, this.onTap});

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.chat_bubble_outline, size: 18),
      label: Text(context.l10n.commentsCount(count)),
      style: TextButton.styleFrom(
        foregroundColor: AnsibleDesign.ink,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: AnsibleDesign.paperDeep,
        shape: const StadiumBorder(),
      ),
    );
  }
}
