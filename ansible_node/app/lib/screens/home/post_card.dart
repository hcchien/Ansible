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
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AnsibleDesign.paperDeep,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 20,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: widget.onOpenAuthor == null
                                ? null
                                : () => widget.onOpenAuthor!(data.author),
                            child: AuthorLabel(
                              did: data.author,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AnsibleDesign.ink,
                              ),
                            ),
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
                              size: 12,
                              color: AnsibleDesign.spore,
                            ),
                          ),
                        ],
                        if (data.authorTier == 'verified_human') ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 13, color: _accent),
                        ],
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '· ${data.board} · ${data.timeAgo}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AnsibleDesign.inkFaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (data.title.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: _hover ? _accent : AnsibleDesign.ink,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      data.content.isEmpty
                          ? context.l10n.noContentYet
                          : data.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AnsibleDesign.inkMuted,
                        height: 1.4,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _ReactionChip(
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
                        const SizedBox(width: 8),
                        _CommentChip(
                          count: data.comments,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PostsViewScreen(
                                  db: widget.db,
                                  thread: thread,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
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
        foregroundColor: active ? AnsibleDesign.spore : AnsibleDesign.inkMuted,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.transparent,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13),
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
      icon: const Icon(Icons.chat_bubble_outline, size: 16),
      label: Text(context.l10n.commentsCount(count)),
      style: TextButton.styleFrom(
        foregroundColor: AnsibleDesign.inkMuted,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.transparent,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13),
      ),
    );
  }
}
