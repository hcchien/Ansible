import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/handle_resolver.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/follow_button.dart';

/// Profile surface for *another* user, with a working follow/unfollow control
/// wired to [FollowService]. Following a user makes their public posts and
/// murmur/note appear in the local Following feed; unfollowing purges that
/// author's follow-only synced content.
///
/// Styled after Threads/IG: avatar + display name + @handle, so a viewer can
/// tell who this is before following. The handle is resolved from the DID via
/// [HandleResolver]; the raw DID is kept as a small, copyable secondary line.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.db,
    required this.followerDid,
    required this.did,
    this.displayName,
    this.resolver,
  });

  final AppDatabase db;
  final String followerDid;
  final String did;
  final String? displayName;

  /// Overridable for tests; defaults to the shared process-wide resolver.
  final HandleResolver? resolver;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late final FollowRepository _followRepo;
  late final DidReputationRepository _reputationRepo;
  late final FollowService _followService;
  late final HandleResolver _resolver;
  FollowButtonStatus _status = FollowButtonStatus.notFollowing;
  String? _targetId;
  String _tier = 'basic';
  String? _handle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _followRepo = DriftFollowRepository(widget.db);
    _reputationRepo = DriftDidReputationRepository(widget.db);
    _resolver = widget.resolver ?? HandleResolver.shared;
    _handle = _resolver.cached(widget.did);
    _followService = FollowService(
      followRepository: _followRepo,
      outboxRepository: DriftFollowActivityOutboxRepository(widget.db),
      boardSyncConfigRepository: DriftBoardSyncConfigRepository(widget.db),
      postRepository: DriftPostRepository(widget.db),
      contentItemRepository: DriftContentItemRepository(widget.db),
    );
    _loadStatus();
    _loadHandle();
  }

  Future<void> _loadHandle() async {
    final handle = await _resolver.handleFor(widget.did);
    if (!mounted || handle == null || handle.isEmpty) return;
    setState(() => _handle = handle);
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
    final tier = await _reputationRepo.tierFor(widget.did);
    if (!mounted) return;
    setState(() {
      _status = status;
      _targetId = targetId;
      _tier = tier;
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
    final passedName = widget.displayName?.trim();
    final hasHandle = _handle != null && _handle!.isNotEmpty;
    // Prefer an explicit display name, else the resolved handle, else a short
    // DID — never show the bare DID as the primary identity.
    final displayName = (passedName != null && passedName.isNotEmpty)
        ? passedName
        : (hasHandle ? _handle! : shortenDid(widget.did));
    final handleLine = hasHandle ? '@${_handle!}' : null;
    final verified = PostingGate.isVerifiedHuman(_tier);
    final humanAssured = PostingGate.isHumanAssured(_tier);
    final assuranceLabel = switch (_tier) {
      PostingGate.uniqueHumanTier => context.uiCopy(
        zh: '強唯一性真人',
        en: 'Unique Human',
      ),
      PostingGate.verifiedHumanTier => context.uiCopy(
        zh: '已驗證真人',
        en: 'Verified Human',
      ),
      PostingGate.humanityLimitedTier => context.uiCopy(
        zh: '有限真人保證',
        en: 'Limited Human Assurance',
      ),
      _ => '',
    };

    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '個人檔案', en: 'PROFILE'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AnsibleDesign.ink,
                            ),
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 18,
                            color: AnsibleDesign.accent,
                          ),
                        ],
                      ],
                    ),
                    if (handleLine != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        handleLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AnsibleDesign.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _Avatar(seed: displayName),
            ],
          ),
          if (humanAssured) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  verified ? Icons.verified : Icons.face_retouching_natural,
                  size: 15,
                  color: AnsibleDesign.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  assuranceLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FollowButton(
              status: _status,
              onPressed: _busy ? null : _onPressed,
            ),
          ),
          const SizedBox(height: 24),
          // Raw DID kept as a small, copyable secondary identifier.
          Text(
            'DID',
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              letterSpacing: 1.4,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            widget.did,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 12,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular avatar placeholder showing the first character of the display
/// identity (handle/name). Mirrors the listing/feed avatar treatment.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.seed});

  final String seed;

  @override
  Widget build(BuildContext context) {
    final trimmed = seed.replaceFirst('@', '').trim();
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.substring(0, 1).toUpperCase();
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AnsibleDesign.paperDeep,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: AnsibleDesign.inkMuted,
        ),
      ),
    );
  }
}
