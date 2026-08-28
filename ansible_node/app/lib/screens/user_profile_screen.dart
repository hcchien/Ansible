import 'dart:async';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/app_view_timeline_client.dart';
import '../services/elix_content_link.dart';
import '../services/elix_content_router.dart';
import '../services/handle_resolver.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/follow_button.dart';
import 'posts_view_screen.dart';
import 'wallet_screen.dart';

typedef PublicProfilePostsLoader =
    Future<List<AppViewTimelineItem>> Function(String did);

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
    this.profileResolver,
    this.publicPostsLoader,
    this.profileProjectionRefreshDelay = const Duration(seconds: 6),
  });

  final AppDatabase db;
  final String followerDid;
  final String did;
  final String? displayName;

  /// Overridable for tests; defaults to the shared process-wide resolver.
  final HandleResolver? resolver;

  /// Public, presentation-only profile resolver. The returned fields are
  /// never used for signing, authorization, or follow-target identity.
  final PublicProfileResolver? profileResolver;

  /// Public, signature-verified author timeline. Tests inject a deterministic
  /// loader; production uses the configured first-party AppView.
  final PublicProfilePostsLoader? publicPostsLoader;

  /// AppView folds Relay profile ops on a short interval. Own-profile reads
  /// retry once across that projection window so a just-synced disclosure
  /// appears without requiring the user to close and reopen the screen.
  final Duration profileProjectionRefreshDelay;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late final FollowRepository _followRepo;
  late final DidReputationRepository _reputationRepo;
  late final FollowService _followService;
  late final HandleResolver _resolver;
  late final PublicProfileResolver _profileResolver;
  FollowButtonStatus _status = FollowButtonStatus.notFollowing;
  String? _targetId;
  String _tier = 'basic';
  String? _handle;
  String? _publishedDisplayName;
  String? _bio;
  String? _publishedTier;
  List<PublicProfileCredential> _publicCredentials = const [];
  bool _hasPublishedProfile = false;
  List<_PublicProfileEntry> _publicPosts = const [];
  String? _publicPostsError;
  bool _loadingPublicPosts = true;
  bool _busy = false;
  Timer? _profileProjectionRefreshTimer;

  @override
  void initState() {
    super.initState();
    _followRepo = DriftFollowRepository(widget.db);
    _reputationRepo = DriftDidReputationRepository(widget.db);
    _resolver = widget.resolver ?? HandleResolver.shared;
    _profileResolver = widget.profileResolver ?? PublicProfileResolver.shared;
    _handle = _resolver.cached(widget.did);
    final cachedProfile = _profileResolver.cached(widget.did);
    _publishedDisplayName = cachedProfile?.displayName;
    _bio = cachedProfile?.bio;
    _hasPublishedProfile = cachedProfile != null;
    if ((cachedProfile?.handle ?? '').isNotEmpty) {
      _handle = cachedProfile!.handle;
    }
    _publishedTier = cachedProfile?.reputationTier;
    _publicCredentials = cachedProfile?.publicCredentials ?? const [];
    _followService = FollowService(
      followRepository: _followRepo,
      outboxRepository: DriftFollowActivityOutboxRepository(widget.db),
      boardSyncConfigRepository: DriftBoardSyncConfigRepository(widget.db),
      postRepository: DriftPostRepository(widget.db),
      contentItemRepository: DriftContentItemRepository(widget.db),
    );
    _loadStatus();
    _loadHandle();
    unawaited(_loadProfile(refresh: true, retryAfterProjection: true));
    _loadPublicPosts();
  }

  @override
  void dispose() {
    _profileProjectionRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile({
    bool refresh = false,
    bool retryAfterProjection = false,
  }) async {
    final profile = await _profileResolver.profileFor(
      widget.did,
      refresh: refresh,
    );
    if (!mounted || profile == null) return;
    setState(() {
      _publishedDisplayName = profile.displayName;
      _bio = profile.bio;
      _hasPublishedProfile = true;
      if ((profile.handle ?? '').isNotEmpty) _handle = profile.handle;
      _publishedTier = profile.reputationTier;
      _publicCredentials = profile.publicCredentials;
    });
    if (retryAfterProjection &&
        widget.did == widget.followerDid &&
        profile.publicCredentials.isEmpty) {
      _profileProjectionRefreshTimer?.cancel();
      _profileProjectionRefreshTimer = Timer(
        widget.profileProjectionRefreshDelay,
        () {
          if (mounted) unawaited(_loadProfile(refresh: true));
        },
      );
    }
  }

  Future<void> _loadPublicPosts() async {
    try {
      final loader = widget.publicPostsLoader ?? _fetchPublicPosts;
      final items = await loader(widget.did);
      if (!mounted) return;
      setState(() {
        _publicPosts = _profileEntries(items);
        _publicPostsError = null;
        _loadingPublicPosts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _publicPostsError = context.uiCopy(
          zh: '暫時無法載入公開貼文',
          en: 'Public posts are temporarily unavailable',
        );
        _loadingPublicPosts = false;
      });
    }
  }

  Future<List<AppViewTimelineItem>> _fetchPublicPosts(String did) async {
    final baseUrl = AppEnvironment.appViewBaseUrl.trim();
    if (baseUrl.isEmpty) return const [];
    final page = await AppViewTimelineClient(
      baseUrl: baseUrl,
    ).fetch(dids: [did], limit: 100);
    return page.items;
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
    final publishedName = _publishedDisplayName?.trim();
    final hasHandle = _handle != null && _handle!.isNotEmpty;
    // Prefer an explicit display name, else the resolved handle, else a short
    // DID — never show the bare DID as the primary identity.
    final displayName = (passedName != null && passedName.isNotEmpty)
        ? passedName
        : (publishedName != null && publishedName.isNotEmpty)
        ? publishedName
        : (hasHandle ? _handle! : shortenDid(widget.did));
    final handleLine = hasHandle ? '@${_handle!}' : null;
    final effectiveTier = (_publishedTier ?? '').isNotEmpty
        ? _publishedTier!
        : _tier;
    final verified = PostingGate.isVerifiedHuman(effectiveTier);
    final humanAssured = PostingGate.isHumanAssured(effectiveTier);
    final assuranceLabel = switch (effectiveTier) {
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          final profile = _buildProfileColumn(
            context,
            displayName: displayName,
            handleLine: handleLine,
            verified: verified,
            humanAssured: humanAssured,
            assuranceLabel: assuranceLabel,
          );
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              desktop ? 32 : 18,
              8,
              desktop ? 32 : 18,
              40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: desktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: profile),
                          const SizedBox(width: 28),
                          SizedBox(
                            width: 300,
                            child: _ProfileContextRail(
                              hasPublishedProfile: _hasPublishedProfile,
                              assuranceLabel: humanAssured
                                  ? assuranceLabel
                                  : null,
                            ),
                          ),
                        ],
                      )
                    : profile,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileColumn(
    BuildContext context, {
    required String displayName,
    required String? handleLine,
    required bool verified,
    required bool humanAssured,
    required String assuranceLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(seed: displayName),
            const SizedBox(width: 16),
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
                            fontFamily: AnsibleDesign.serif,
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
                    const SizedBox(height: 3),
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
                  const SizedBox(height: 6),
                  SelectableText(
                    widget.did,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10.5,
                      color: AnsibleDesign.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if ((_bio ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _bio!.trim(),
            style: const TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 14.5,
              height: 1.65,
              color: AnsibleDesign.ink,
            ),
          ),
        ],
        if (_hasPublishedProfile ||
            humanAssured ||
            _publicCredentials.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_hasPublishedProfile)
                _ProfileBadge(
                  icon: Icons.public,
                  label: context.uiCopy(zh: '公開 Profile', en: 'Public profile'),
                ),
              if (humanAssured)
                _ProfileBadge(
                  icon: verified
                      ? Icons.verified
                      : Icons.face_retouching_natural,
                  label: assuranceLabel,
                ),
              for (final credential in _publicCredentials)
                _ProfileBadge(
                  icon: Icons.verified_user_outlined,
                  label: _publicCredentialLabel(context, credential),
                ),
            ],
          ),
        ],
        if (widget.did == widget.followerDid) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _openCredentialManager,
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: Text(
              context.uiCopy(
                zh: '管理個人檔案上的證明',
                en: 'Manage profile credentials',
              ),
            ),
          ),
        ],
        if (widget.did != widget.followerDid) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FollowButton(
              status: _status,
              onPressed: _busy ? null : _onPressed,
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(height: 1, color: AnsibleDesign.ruleSoft),
        const SizedBox(height: 18),
        Text(
          context.uiCopy(zh: '公開貼文', en: 'PUBLIC POSTS'),
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 10,
            letterSpacing: 1.3,
            color: AnsibleDesign.inkFaint,
          ),
        ),
        const SizedBox(height: 10),
        if (_loadingPublicPosts)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_publicPostsError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              _publicPostsError!,
              style: const TextStyle(color: AnsibleDesign.inkMuted),
            ),
          )
        else if (_publicPosts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              context.uiCopy(zh: '目前沒有公開貼文', en: 'No public posts yet'),
              style: const TextStyle(color: AnsibleDesign.inkMuted),
            ),
          )
        else
          for (final post in _publicPosts) ...[
            _PublicProfilePostCard(
              entry: post,
              onTap: post.isDiscussion ? () => _openDiscussion(post) : null,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  String _publicCredentialLabel(
    BuildContext context,
    PublicProfileCredential credential,
  ) {
    return switch (credential.badge) {
      'age_over_18' => context.uiCopy(zh: '已滿 18 歲', en: 'Age 18+'),
      'nationality' => context.uiCopy(
        zh: '國籍 · ${credential.value}',
        en: 'Nationality · ${credential.value}',
      ),
      'taiwan_citizenship' => context.uiCopy(zh: '台灣公民', en: 'Taiwan citizen'),
      'human_assurance' => switch (credential.value) {
        PostingGate.uniqueHumanTier => context.uiCopy(
          zh: '強唯一性真人',
          en: 'Unique Human',
        ),
        PostingGate.humanityLimitedTier => context.uiCopy(
          zh: '有限真人保證',
          en: 'Limited Human Assurance',
        ),
        _ => context.uiCopy(zh: '已驗證真人', en: 'Verified Human'),
      },
      _ => credential.credentialType,
    };
  }

  Future<void> _openCredentialManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalletScreen(
          holderDid: widget.followerDid,
          repository: DriftWalletRepository(widget.db),
          db: widget.db,
        ),
      ),
    );
    if (!mounted) return;
    await _loadProfile(refresh: true, retryAfterProjection: true);
  }

  Future<void> _openDiscussion(_PublicProfileEntry entry) async {
    final boardId = entry.boardId;
    final threadId = entry.threadId;
    if (boardId == null || threadId == null) return;
    final resolution = await ElixContentRouter(
      widget.db,
    ).resolve(ElixContentRef.thread(boardId: boardId, thread: threadId));
    if (!mounted) return;
    if (resolution is ResolvedThread) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PostsViewScreen(
            db: widget.db,
            thread: resolution.thread,
            authorDid: widget.followerDid,
            screenStyle: ElixScreenStyle.forAppBrightness(
              Theme.of(context).brightness,
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '請先訂閱這個看板，才能在 App 內開啟完整討論',
            en: 'Follow this board to open the full discussion in the app',
          ),
        ),
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AnsibleDesign.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AnsibleDesign.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileContextRail extends StatelessWidget {
  const _ProfileContextRail({
    required this.hasPublishedProfile,
    required this.assuranceLabel,
  });

  final bool hasPublishedProfile;
  final String? assuranceLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileRailCard(
          title: context.uiCopy(zh: '公開身分', en: 'PUBLIC IDENTITY'),
          child: Text(
            hasPublishedProfile
                ? context.uiCopy(
                    zh: '這裡只顯示對方主動發布的名稱、handle、簡介與公開貼文。私鑰與原始憑證不會進入這個頁面。',
                    en: 'This page shows only the name, handle, bio, and posts the person chose to publish. Private keys and raw credentials never enter this surface.',
                  )
                : context.uiCopy(
                    zh: '這個身分尚未發布公開 profile；仍可閱讀它已公開簽署的貼文。',
                    en: 'This identity has not published a public profile. Its signed public posts can still be read.',
                  ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 13,
              height: 1.65,
              color: AnsibleDesign.inkMuted,
            ),
          ),
        ),
        if (assuranceLabel != null) ...[
          const SizedBox(height: 14),
          _ProfileRailCard(
            title: context.uiCopy(zh: '信任層級', en: 'TRUST TIER'),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 17,
                  color: AnsibleDesign.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    assuranceLabel!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AnsibleDesign.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ProfileRailCard extends StatelessWidget {
  const _ProfileRailCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              letterSpacing: 1.3,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

List<_PublicProfileEntry> _profileEntries(List<AppViewTimelineItem> items) {
  bool isPublic(AppViewTimelineItem item) {
    final visibility = item.visibility?.trim().toLowerCase();
    return visibility == null || visibility.isEmpty || visibility == 'public';
  }

  String? value(Object? raw) {
    final text = raw?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  final visible = items.where(isPublic).toList();
  final threads = <String, AppViewTimelineItem>{
    for (final item in visible.where((item) => item.entityType == 'thread'))
      item.entityId: item,
  };
  final entries = <String, _PublicProfileEntry>{};

  for (final item in visible) {
    switch (item.entityType) {
      case 'post':
        if (value(item.payload['parentPostId']) != null) continue;
        final threadId =
            value(item.threadId) ?? value(item.payload['threadId']);
        final boardId = value(item.boardId) ?? value(item.payload['boardId']);
        if (threadId == null || boardId == null) continue;
        final thread = threads[threadId];
        entries['thread:$threadId'] = _PublicProfileEntry(
          id: item.entityId,
          type: 'post',
          title:
              value(item.payload['title']) ??
              value(item.payload['threadTitle']) ??
              value(thread?.payload['title']),
          body:
              value(item.payload['content']) ??
              value(thread?.payload['description']) ??
              '',
          boardId: boardId,
          threadId: threadId,
          createdAt: item.createdAt ?? thread?.createdAt,
        );
        break;
      case 'thread':
        final threadId = item.entityId;
        entries.putIfAbsent(
          'thread:$threadId',
          () => _PublicProfileEntry(
            id: item.entityId,
            type: 'post',
            title: value(item.payload['title']),
            body: value(item.payload['description']) ?? '',
            boardId: value(item.boardId) ?? value(item.payload['boardId']),
            threadId: threadId,
            createdAt: item.createdAt,
          ),
        );
        break;
      case 'murmur':
      case 'note':
        entries['${item.entityType}:${item.entityId}'] = _PublicProfileEntry(
          id: item.entityId,
          type: item.entityType,
          title: value(item.payload['title']),
          body: value(item.payload['body']) ?? '',
          createdAt: item.createdAt,
        );
        break;
      default:
        break;
    }
  }

  final result = entries.values.toList()
    ..sort((a, b) {
      final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
  return result;
}

class _PublicProfileEntry {
  const _PublicProfileEntry({
    required this.id,
    required this.type,
    required this.body,
    this.title,
    this.boardId,
    this.threadId,
    this.createdAt,
  });

  final String id;
  final String type;
  final String? title;
  final String body;
  final String? boardId;
  final String? threadId;
  final DateTime? createdAt;

  bool get isDiscussion => type == 'post';
}

class _PublicProfilePostCard extends StatelessWidget {
  const _PublicProfilePostCard({required this.entry, this.onTap});

  final _PublicProfileEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (entry.type) {
      'note' => 'NOTE',
      'murmur' => 'MURMUR',
      _ => context.uiCopy(zh: '討論', en: 'DISCUSSION'),
    };
    final date = entry.createdAt?.toLocal();
    final dateLabel = date == null
        ? ''
        : '${date.year}/${date.month}/${date.day}';
    return Material(
      key: Key('public_profile_post_${entry.id}'),
      color: AnsibleDesign.paperElev,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    typeLabel,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 9,
                      letterSpacing: 1.2,
                      color: AnsibleDesign.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  if (dateLabel.isNotEmpty)
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 10,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AnsibleDesign.inkFaint,
                    ),
                  ],
                ],
              ),
              if ((entry.title ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.title!,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AnsibleDesign.ink,
                  ),
                ),
              ],
              if (entry.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry.body,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14,
                    height: 1.65,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
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
