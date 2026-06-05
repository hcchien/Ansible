import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../widgets/follow_button.dart';

/// Minimal profile surface for *another* user, with a working follow/unfollow
/// control wired to [FollowService]. Following a user makes their public posts
/// and murmur/note appear in the local Following feed; unfollowing purges that
/// author's follow-only synced content.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.db,
    required this.followerDid,
    required this.did,
    this.displayName,
  });

  final AppDatabase db;
  final String followerDid;
  final String did;
  final String? displayName;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late final FollowRepository _followRepo;
  late final FollowService _followService;
  FollowButtonStatus _status = FollowButtonStatus.notFollowing;
  String? _targetId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _followRepo = DriftFollowRepository(widget.db);
    _followService = FollowService(
      followRepository: _followRepo,
      outboxRepository: DriftFollowActivityOutboxRepository(widget.db),
      boardSyncConfigRepository: DriftBoardSyncConfigRepository(widget.db),
      postRepository: DriftPostRepository(widget.db),
      contentItemRepository: DriftContentItemRepository(widget.db),
    );
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final target = await _followRepo.getTargetByCanonicalUri(widget.did);
    FollowButtonStatus status = FollowButtonStatus.notFollowing;
    String? targetId = target?.targetId;
    if (target != null) {
      final edge = await _followRepo.getEdge(
        widget.followerDid,
        target.targetId,
        FollowDirection.outbound,
      );
      status = _mapStatus(edge?.status);
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _targetId = targetId;
    });
  }

  FollowButtonStatus _mapStatus(FollowStatus? status) {
    return switch (status) {
      FollowStatus.accepted => FollowButtonStatus.following,
      FollowStatus.pending => FollowButtonStatus.requested,
      FollowStatus.failed => FollowButtonStatus.failed,
      FollowStatus.blocked => FollowButtonStatus.blocked,
      _ => FollowButtonStatus.notFollowing,
    };
  }

  Future<void> _onPressed() async {
    if (_busy) return;
    setState(() => _busy = true);
    final now = DateTime.now().toUtc();
    try {
      switch (_status) {
        case FollowButtonStatus.notFollowing:
        case FollowButtonStatus.failed:
          await _followService.followUser(
            followerDid: widget.followerDid,
            targetDid: widget.did,
            displayName: widget.displayName ?? widget.did,
            now: now,
          );
        case FollowButtonStatus.following:
        case FollowButtonStatus.requested:
          if (_targetId != null) {
            await _followService.unfollow(
              followerDid: widget.followerDid,
              targetId: _targetId!,
              now: now,
            );
          }
        case FollowButtonStatus.blocked:
          break;
      }
      await _loadStatus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.displayName != null &&
            widget.displayName!.trim().isNotEmpty)
        ? widget.displayName!
        : widget.did;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            SelectableText(
              widget.did,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            FollowButton(
              status: _status,
              onPressed: _busy ? null : _onPressed,
            ),
          ],
        ),
      ),
    );
  }
}
