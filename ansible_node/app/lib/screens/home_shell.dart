import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../widgets/agent_sheet.dart';
import '../widgets/board_form_dialog.dart';
import '../services/atproto_client.dart';
import '../services/recovery_veto_service.dart';
import '../services/relay_anchor_client.dart';
import '../widgets/recovery_veto_alert.dart';
import '../services/ai/ai_provider.dart';
import '../services/ai/ai_provider_config_store.dart';
import '../services/ai/apple_nl_embedding_service.dart';
import '../services/ai/manual_ai_provider.dart';
import '../services/ai/murmur_indexing_service.dart';
import '../services/ai/openai_compatible_provider.dart';
import '../services/ai/vector_search_service.dart';
import '../services/app_locale_controller.dart';
import '../services/app_view_timeline_client.dart';
import '../services/app_sync_service.dart';
import '../services/board_access_presentation_service.dart';
import '../services/contact_resolver.dart';
import '../services/discovery_client.dart';
import '../services/contact_source_sync_service.dart';
import '../services/messenger_contact_resolver.dart';
import '../services/messenger_device_service.dart';
import '../services/messenger_relay_client.dart';
import '../services/messenger_sync_service.dart';
import '../services/network_status_service.dart';
import '../services/ops_dispatch_service.dart';
import '../services/content_publication_service.dart';
import '../services/forum_host_client.dart';
import '../services/forum_publication_service.dart';
import '../services/host_moderation_sync_service.dart';
import '../services/nostr_relay_settings_store.dart';
import '../services/nostr_secure_key_store.dart';
import '../services/notification_preferences_controller.dart';
import '../services/notification_projector.dart';
import '../services/local_notification_rebuilder.dart';
import '../services/private_board_op_factory.dart';
import '../services/private_board_crypto_service.dart';
import '../services/private_board_key_client.dart';
import '../services/relay_discovery_client.dart';
import '../services/reading_preferences_controller.dart';
import '../services/relay_ops_client.dart';
import '../services/relay_reputation_presentation_service.dart';
import '../services/user_presence_verifier.dart';
import '../services/sync_capability_service.dart';
import '../widgets/ai_provider_setup_sheet.dart';
import '../widgets/feed_filter_tabs.dart';
import 'notifications_screen.dart';
import 'sync_settings_screen.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import 'discover_screen.dart';
import 'hosted_boards_screen.dart';
import 'settings_home_screen.dart';
import 'threads_list_screen.dart';
import 'thread_composer_screen.dart';
import 'home/circle_full_screen.dart';
import 'home/compose_action_item.dart';
import 'home/home_bottom_bar.dart';
import 'home/home_types.dart';
import 'home/main_panel.dart';
import 'home/post_card.dart';
import 'home/screen_style_sheet.dart';
import 'home/sidebar.dart';

export 'home/home_types.dart';
export 'home/post_card.dart' show PostCard, PostCardData;

/// Bottom-nav destinations on the compact (phone) shell. Boards live in the
/// swipe pager; notifications + me are sibling in-shell panels so the bottom
/// nav stays mounted across all of them (Threads-style), instead of pushing a
/// route that covers the bar.
enum _ShellDest { board, notifications, me }

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    required this.did,
    this.publicKeyHex,
    this.onClearIdentity,
    this.syncRunner,
    this.pullRefreshRunner,
    this.relayDiscoveryLoader,
    this.defaultSubscriptionsDiscoveryLoader,
    this.networkStatusMonitor,
    this.userPresenceVerifier,
    this.localeController,
    this.readingPreferencesController,
    this.autoSeedDefaultRelay = true,
    this.initialBoard = HomeBoard.timeline,
  });

  /// Board shown on launch. Defaults to the Timeline (時間軸); overridable so
  /// tests can land on a specific board.
  final HomeBoard initialBoard;

  final AppDatabase db;
  final String did;
  final String? publicKeyHex;

  /// When true (default), a default relay node is seeded on first run if the
  /// local node list is empty. Tests that assert first-run-without-relay set
  /// this to false.
  final bool autoSeedDefaultRelay;
  final VoidCallback? onClearIdentity;
  final Future<AppSyncResult> Function()? syncRunner;
  final Future<RelayPullSummary> Function()? pullRefreshRunner;
  final Future<RelayDiscovery> Function()? relayDiscoveryLoader;
  final Future<RelayDiscovery> Function()? defaultSubscriptionsDiscoveryLoader;
  final NetworkStatusMonitor? networkStatusMonitor;
  final UserPresenceVerifier? userPresenceVerifier;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final DriftBoardRepository _boardRepo;
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;
  late final DriftReactionRepository _reactionRepo;
  late final DriftFollowRepository _followRepo;
  late final DriftContactRepository _contactRepo;
  late final DriftMessengerRepository _messengerRepo;
  late final MessengerRelayClient _messengerRelayClient;
  late final MessengerDeviceService _messengerDeviceService;
  late final MessengerSyncService _messengerSyncService;
  late final store.NotificationRepository _notificationRepo;
  late final NotificationPreferencesController _notificationPrefs;
  late final NotificationProjector _notificationProjector;
  late final LocalNotificationRebuilder _notificationRebuilder;
  int _notificationUnreadCount = 0;
  bool _notificationBackfillDone = false;
  late final MessengerContactResolver _messengerContactResolver;
  late final ContactResolver _contactResolver;
  late final DriftRemoteNodeRepository _remoteNodeRepo;
  late final DriftOpsQueueRepository _opsQueueRepo;
  late final DriftContentItemRepository _contentItemRepo;
  late final DriftDidReputationRepository _didReputationRepo;
  late final DriftContentRelationRepository _contentRelationRepo;
  late final DriftPublicationRepository _publicationRepo;
  late final DriftForumHostRepository _forumHostRepo;
  late final DriftHostedBoardRepository _hostedBoardRepo;
  late final DriftAiProviderConfigRepository _aiProviderConfigRepo;
  late final AiProviderConfigStore _aiProviderConfigStore;
  late final AppleNLEmbeddingService _embeddingService;
  late final DriftMurmurEmbeddingRepository _murmurEmbeddingRepo;
  late final MurmurIndexingService _murmurIndexingService;
  late final VectorSearchService _vectorSearchService;
  late final SecureStorageNostrKeyStore _nostrKeyStore;
  late final SecureStorageNostrRelaySettingsStore _nostrRelaySettingsStore;
  late final OpsDispatchService _opsDispatchService;
  late final AtProtoClient _atProtoClient;
  late final NetworkStatusMonitor _networkStatusService;
  late final bool _ownsNetworkStatusService;

  List<Board> _boards = [];
  List<PostCardData> _posts = [];
  // Following timeline (時間軸 board) — computed independently of the forum board
  // so both can render simultaneously in the swipe pager.
  List<PostCardData> _followingPosts = [];
  List<ContentItem> _contentItems = [];
  Map<String, int> _murmurReferenceCounts = const {};
  bool _loading = true;
  bool _syncing = false;
  bool _pullRefreshing = false;
  bool _hasActiveMessengerRelay = false;
  bool _showFirstRunDiscovery = false;
  bool _relayDiscoveryLoading = false;
  bool _relayDiscoveryLoaded = false;
  RelayDiscovery? _relayDiscovery;
  NetworkStatus? _lastNetworkStatus;
  DateTime? _lastAutoSyncAt;
  String? _selectedBoardId;
  FeedFilter _feedFilter = FeedFilter.all;
  PersonalFilter _personalFilter = PersonalFilter.all;
  ElixTab _selectedTab = ElixTab.feed;
  late HomeBoard _selectedBoard;
  // Active compact bottom-nav destination (boards pager / notifications / me).
  _ShellDest _dest = _ShellDest.board;
  bool _mobileNavigationVisible = true;
  ElixBoardMotion _boardMotion = ElixBoardMotion.book;
  bool _showCoachmark = false;
  CircleTab _selectedCircleTab = CircleTab.murmur;
  late final PageController _pageController;
  Map<ElixTab, ElixScreenStyle> _screenStyles = {
    for (final tab in ElixTab.values) tab: ElixScreenStyle.paper,
  };
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    // Default landing screen is the Timeline (時間軸), not the personal board.
    _selectedBoard = widget.initialBoard;
    _pageController = PageController(initialPage: widget.initialBoard.index);
    _boardRepo = DriftBoardRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _reactionRepo = DriftReactionRepository(widget.db);
    _followRepo = DriftFollowRepository(widget.db);
    _contactRepo = DriftContactRepository(widget.db);
    _messengerRepo = DriftMessengerRepository(widget.db);
    _messengerRelayClient = MessengerRelayClient();
    _messengerDeviceService = MessengerDeviceService(
      repository: _messengerRepo,
      relayClient: _messengerRelayClient,
    );
    _notificationRepo = store.DriftNotificationRepository(widget.db);
    _notificationPrefs = NotificationPreferencesController();
    _notificationProjector = NotificationProjector(
      notifications: _notificationRepo,
      localDid: widget.did,
      threadRepository: _threadRepo,
      postRepository: _postRepo,
      contactRepository: _contactRepo,
      isCategoryEnabled: _notificationPrefs.categoryEnabled,
    );
    _notificationRebuilder = LocalNotificationRebuilder(
      notifications: _notificationRepo,
      threads: _threadRepo,
      posts: _postRepo,
      messenger: _messengerRepo,
      localDid: widget.did,
    );
    _messengerSyncService = MessengerSyncService(
      repository: _messengerRepo,
      contactRepository: _contactRepo,
      deviceService: _messengerDeviceService,
      relayClient: _messengerRelayClient,
      crypto: _messengerDeviceService.crypto,
      didSigner: DidSignerImpl(),
      notificationProjector: _notificationProjector,
    );
    _messengerContactResolver = MessengerContactResolver(
      relayClient: _messengerRelayClient,
    );
    _contactResolver = ContactResolver(repository: _contactRepo);
    _remoteNodeRepo = DriftRemoteNodeRepository(widget.db);
    _opsQueueRepo = DriftOpsQueueRepository(widget.db);
    _contentItemRepo = DriftContentItemRepository(widget.db);
    _didReputationRepo = DriftDidReputationRepository(widget.db);
    _contentRelationRepo = DriftContentRelationRepository(widget.db);
    _publicationRepo = DriftPublicationRepository(widget.db);
    _forumHostRepo = DriftForumHostRepository(widget.db);
    _hostedBoardRepo = DriftHostedBoardRepository(widget.db);
    _aiProviderConfigRepo = DriftAiProviderConfigRepository(widget.db);
    _aiProviderConfigStore = AiProviderConfigStore(
      repository: _aiProviderConfigRepo,
    );
    _embeddingService = const AppleNLEmbeddingService();
    _murmurEmbeddingRepo = DriftMurmurEmbeddingRepository(widget.db);
    _murmurIndexingService = MurmurIndexingService(
      embeddingService: _embeddingService,
      embeddingRepository: _murmurEmbeddingRepo,
      contentItemRepository: _contentItemRepo,
    );
    _vectorSearchService = VectorSearchService(
      embeddingService: _embeddingService,
      embeddingRepository: _murmurEmbeddingRepo,
      contentItemRepository: _contentItemRepo,
    );
    _nostrKeyStore = const SecureStorageNostrKeyStore();
    _nostrRelaySettingsStore = const SecureStorageNostrRelaySettingsStore();
    _opsDispatchService = OpsDispatchService(repository: _opsQueueRepo);
    _atProtoClient = AtProtoClient();
    _networkStatusService =
        widget.networkStatusMonitor ?? NetworkStatusService();
    _ownsNetworkStatusService = widget.networkStatusMonitor == null;
    _lastNetworkStatus = _networkStatusService.status;
    _networkStatusService.addListener(_handleNetworkStatusChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Seed the default relay (from the build config) on a fresh install so the
      // app can sync out-of-box without the user manually adding a relay.
      await _ensureDefaultRelayNode();
      if (!mounted) return;
      unawaited(_loadScreenStyles());
      unawaited(_loadBoardMotion());
      unawaited(_loadData());
      // Subscription/projection setup must finish before the first relay pull.
      // Otherwise the pull filters out historical board ops, then only the
      // empty local board shells are rendered until a later resume/manual sync.
      unawaited(_bootstrapForumAndPull());
      unawaited(_murmurIndexingService.indexAllPending());
      unawaited(_checkCoachmark());
      // Hijack resistance (recovery design, conflict-priority #1): if a
      // recovery re-anchor for OUR DID is sitting in its grace window, alert
      // immediately with a one-tap veto.
      unawaited(_checkPendingRecovery());
    });
  }

  /// Restores forum routing state before the first history pull.
  ///
  /// Ordering is intentional: [RemoteSyncService] only materializes hosted
  /// thread/post ops when a matching subscription + projection already exists.
  /// Keeping this as one awaited chain prevents a fresh install from racing the
  /// default-subscription and created-board reconciliation tasks against pull.
  Future<void> _bootstrapForumAndPull() async {
    await _ensureDefaultSubscriptions();
    await _repairHostedBoardHistoryCursors();
    if (!mounted) return;
    await _loadData();
    await _runForegroundPullIfConfigured();

    // Creator reconciliation may involve a slower Forum Host query. Do it
    // after featured boards have already become readable, then pull once more
    // only when it actually restored additional subscriptions.
    final subscriptionsBefore =
        (await _hostedBoardRepo.listSubscriptions()).length;
    await _reconcileCreatedBoards();
    final subscriptionsAfter =
        (await _hostedBoardRepo.listSubscriptions()).length;
    if (!mounted) return;
    if (subscriptionsAfter > subscriptionsBefore) {
      await _loadData();
      await _runForegroundPullIfConfigured();
    }

    // Anchoring is required for later writes, not for reading public history.
    // Keep it best-effort and non-blocking so a slow identity endpoint cannot
    // delay the first board projection.
    unawaited(_ensureAnchored());
  }

  bool _vetoAlertShowing = false;

  /// Polls the relay for a pending recovery re-anchor of this DID and, when
  /// found, shows the veto alert. Failures are silent — this is a background
  /// safety poll; the next launch/wake retries.
  Future<void> _checkPendingRecovery() async {
    if (_vetoAlertShowing) return;
    final vetoService = RecoveryVetoService(
      relayClient: RelayAnchorClient(
        baseUrl: AppEnvironment.defaultRelayBaseUrl,
      ),
    );
    final pending = await vetoService.checkPending(widget.did);
    if (pending == null || !mounted || _vetoAlertShowing) return;
    _vetoAlertShowing = true;
    try {
      await showRecoveryVetoAlert(
        context,
        did: widget.did,
        pending: pending,
        vetoService: vetoService,
      );
    } finally {
      _vetoAlertShowing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkStatusService.removeListener(_handleNetworkStatusChanged);
    if (_ownsNetworkStatusService) {
      _networkStatusService.dispose();
    }
    _pageController.dispose();
    _messengerRelayClient.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runForegroundPullIfConfigured());
      // A content-free identity_alert wake resumes the app here — re-check
      // for a pending recovery so the veto alert appears without a restart.
      unawaited(_checkPendingRecovery());
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final l10n = context.l10n;
    await ContactSourceSyncService(
      followRepository: _followRepo,
      contactRepository: _contactRepo,
      messengerRepository: _messengerRepo,
    ).syncForIdentity(widget.did);
    if (!_notificationBackfillDone) {
      await _notificationRebuilder.rebuild();
      _notificationBackfillDone = true;
    }
    await _refreshNotificationUnread();
    final remoteNodes = await _remoteNodeRepo.list();
    final hasActiveRemoteNode = remoteNodes.any((node) => node.isActive);
    final hasActiveForumHost = (await _forumHostRepo.listActive()).isNotEmpty;
    final hostedBoardProjections = await _hostedBoardRepo.listProjections();
    final hostedBoardSubscriptions = await _hostedBoardRepo.listSubscriptions();
    final hasHostedBoards =
        hostedBoardProjections.any((projection) => !projection.isDeleted) ||
        hostedBoardSubscriptions.isNotEmpty;
    final hasActiveRelay = hasActiveRemoteNode || hasActiveForumHost;
    final showFirstRunDiscovery = !hasActiveRelay && !hasHostedBoards;
    final boards = await _boardRepo.list();
    final contentItems = await _contentItemRepo.list(authorDid: widget.did);
    final murmurReferenceCounts = <String, int>{};
    for (final item in contentItems) {
      if (item.mode != ContentMode.murmur) continue;
      murmurReferenceCounts[item.id] = (await _contentRelationRepo.derivedFrom(
        item.id,
      )).length;
    }
    final boardMap = {for (final b in boards) b.id: b};
    final threads = await _threadRepo.list(boardId: _selectedBoardId);
    // preload posts per thread for content preview and counts
    final firstPosts = <String, Post?>{};
    final postCounts = <String, int>{};
    final reactionCounts = <String, Map<String, int>>{};
    final userReacted = <String, bool>{};
    for (final t in threads) {
      if (!firstPosts.containsKey(t.id)) {
        final posts = await _postRepo.list(threadId: t.id);
        firstPosts[t.id] = posts.isNotEmpty ? posts.first : null;
        // The first row is the opening post; the comment badge counts replies
        // only, matching the thread detail header.
        postCounts[t.id] = replyCountForPosts(posts);

        final reactions = await _reactionRepo.listByTarget(
          store.TargetType.thread.name,
          t.id,
        );
        final countMap = <String, int>{};
        for (final r in reactions) {
          countMap[r.reactionType.name] =
              (countMap[r.reactionType.name] ?? 0) + 1;
          if (r.userId == widget.did &&
              r.reactionType == store.ReactionType.thumbsUp) {
            userReacted[t.id] = true;
          }
        }
        reactionCounts[t.id] = countMap;
      }
    }

    threads.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    // Forum board (討論區): board threads.
    final forumCards = threads.map((t) {
      final board = boardMap[t.boardId];
      final content = firstPosts[t.id]?.content ?? '';
      final comments = postCounts[t.id] ?? 0;
      final counts = reactionCounts[t.id] ?? const {};
      return PostCardData(
        thread: t,
        category: board?.title ?? l10n.uncategorized,
        title: t.title,
        author: t.authorId,
        board: board?.title ?? t.boardId,
        timeAgo: _formatTimeAgo(t.createdAt),
        content: content,
        reactions: {'👍': counts[store.ReactionType.thumbsUp.name] ?? 0},
        comments: comments,
        reacted: userReacted[t.id] ?? false,
        openingPost: firstPosts[t.id],
        signatureVerified: firstPosts[t.id]?.signatureVerified ?? false,
      );
    }).toList();

    // Timeline board (時間軸): posts from people you follow. Best-effort — a
    // discovery/AppView outage just yields an empty timeline, never an error.
    List<PostCardData> followingCards = const [];
    try {
      final followingEntries = await _dynamicWallItems(limit: 100);
      followingCards = await _buildFollowingPostCards(
        followingEntries,
        boardMap,
      );
    } catch (_) {
      followingCards = const [];
    }

    // Local-first home: locally stored public content remains readable without
    // a network, while online AppView results enrich the same wall. De-duplicate
    // by content/thread id because a synced local item may also be in AppView.
    final localWallCards = <PostCardData>[
      ...forumCards,
      ...contentItems
          .where(
            (item) =>
                item.status == ContentStatus.active &&
                !item.localOnly &&
                (item.visibility == ContentVisibility.public ||
                    item.visibility == ContentVisibility.unlisted),
          )
          .map(_contentFollowCard),
    ];
    followingCards = _mergeDynamicWallCards(followingCards, localWallCards);

    // Annotate both lists with their author's reputation tier (verified badge).
    final authorTiers = await _didReputationRepo.tiersFor({
      ...forumCards.map((card) => card.author),
      ...followingCards.map((card) => card.author),
    });
    PostCardData withTier(PostCardData card) =>
        card.copyWith(authorTier: authorTiers[card.author] ?? 'basic');
    final forumTiered = forumCards.map(withTier).toList();
    final followingTiered = followingCards.map(withTier).toList();

    setState(() {
      _boards = boards;
      _posts = forumTiered;
      _followingPosts = followingTiered;
      _contentItems = contentItems;
      _murmurReferenceCounts = murmurReferenceCounts;
      _hasActiveMessengerRelay = hasActiveRelay;
      _showFirstRunDiscovery = showFirstRunDiscovery;
      if (!showFirstRunDiscovery) {
        _relayDiscovery = null;
        _relayDiscoveryLoading = false;
        _relayDiscoveryLoaded = false;
      }
      _loading = false;
    });
    if (showFirstRunDiscovery) {
      unawaited(_loadRelayDiscoveryIfNeeded());
    }
  }

  Future<void> _loadRelayDiscoveryIfNeeded() async {
    if (_relayDiscoveryLoading || _relayDiscoveryLoaded) return;
    setState(() => _relayDiscoveryLoading = true);
    try {
      final discovery =
          await (widget.relayDiscoveryLoader ?? _fetchDefaultRelayDiscovery)();
      if (!mounted) return;
      setState(() {
        _relayDiscovery = discovery;
        _relayDiscoveryLoaded = true;
        _relayDiscoveryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _relayDiscovery = null;
        _relayDiscoveryLoaded = true;
        _relayDiscoveryLoading = false;
      });
    }
  }

  Future<RelayDiscovery> _fetchDefaultRelayDiscovery() async {
    final client = RelayDiscoveryClient(
      baseUrl: AppEnvironment.defaultRelayBaseUrl,
    );
    try {
      return await client.fetchDiscovery();
    } finally {
      client.close();
    }
  }

  static const _genesisSubscribedKey = 'elix-genesis-subscribed';
  static const _hostedBoardHistoryCursorRepairKey =
      'elix-hosted-board-history-cursor-repair-v2';

  /// Repairs installs where the old node-wide cursor advanced before hosted
  /// board subscriptions existed. Resetting once makes the next pull replay
  /// history; a failed pull leaves the cursor at zero, so a later pull retries.
  Future<void> _repairHostedBoardHistoryCursors() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_hostedBoardHistoryCursorRepairKey) ?? false) return;

    final now = DateTime.now();
    final subscriptions = await _hostedBoardRepo.listSubscriptions();
    for (final subscription in subscriptions.where(
      (item) => item.readEnabled,
    )) {
      await _hostedBoardRepo.updateSubscriptionCursor(
        subscription.subscriptionId,
        0,
        now,
      );
    }
    await prefs.setBool(_hostedBoardHistoryCursorRepairKey, true);
  }

  /// First-run default subscriptions (cold-start): when this install has no
  /// hosted-board subscriptions yet, subscribe the relay's featured (genesis)
  /// boards so the forum isn't a ghost town on day one. Runs once per install
  /// (prefs-flagged) and never overrides a user's own subscription state —
  /// unsubscribing later sticks. Best-effort: any failure just leaves the
  /// user on the normal Discover path.
  Future<void> _ensureDefaultSubscriptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_genesisSubscribedKey) ?? false) return;

      final existing = await _hostedBoardRepo.listSubscriptions();
      if (existing.isNotEmpty) {
        await prefs.setBool(_genesisSubscribedKey, true);
        return;
      }

      final hosts = (await _remoteNodeRepo.list())
          .where((n) => n.isActive)
          .toList();
      if (hosts.isEmpty) return;
      final host = hosts.first;

      final loader = widget.defaultSubscriptionsDiscoveryLoader;
      final discovery = loader == null
          ? await _fetchDefaultRelayDiscovery()
          : await loader();
      // Compliance-consuming ranking (compliance-review gap #2): prefer
      // boards on hosts with a higher declared constitution compliance,
      // keeping the relay's featured order within each level.
      final complianceByHostUrl = {
        for (final host in discovery.featuredForumHosts)
          host.forumHostUrl: host.constitutionCompliance,
      };
      int complianceRank(String level) => switch (level) {
        'full' => 0,
        'partial' => 1,
        _ => 2,
      };
      final ranked = List.of(discovery.featuredBoards);
      final originalIndex = {
        for (var i = 0; i < ranked.length; i++) ranked[i]: i,
      };
      ranked.sort((a, b) {
        final byCompliance =
            complianceRank(
              complianceByHostUrl[a.forumHostUrl] ?? 'unknown',
            ).compareTo(
              complianceRank(complianceByHostUrl[b.forumHostUrl] ?? 'unknown'),
            );
        if (byCompliance != 0) return byCompliance;
        return originalIndex[a]!.compareTo(originalIndex[b]!);
      });
      final featured = ranked.take(3).toList();
      if (featured.isEmpty) return;

      final now = DateTime.now();
      for (final board in featured) {
        final localBoardId = '${host.id}_${board.hostedBoardId}';
        try {
          await _boardRepo.create(
            Board(
              id: localBoardId,
              slug: localBoardId,
              title: board.title,
              description: board.description,
              createdAt: now,
              updatedAt: now,
            ),
          );
        } catch (_) {
          // Board row may already exist; continue.
        }
        await _hostedBoardRepo.upsertProjection(
          HostedBoardProjection(
            localBoardId: localBoardId,
            forumHostId: host.id,
            hostedBoardId: board.hostedBoardId,
            canonicalBoardUri: board.canonicalBoardUri,
            remoteSlug: board.hostedBoardId,
            localSlug: localBoardId,
            title: board.title,
            description: board.description,
            permissions: const {'read': true, 'write': true},
            postingPolicy: const {},
            createdAt: now,
            updatedAt: now,
          ),
        );
        await _hostedBoardRepo.upsertSubscription(
          BoardSubscription(
            subscriptionId: localBoardId,
            forumHostId: host.id,
            hostedBoardId: board.hostedBoardId,
            localBoardId: localBoardId,
            readEnabled: true,
            writeEnabled: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await prefs.setBool(_genesisSubscribedKey, true);
    } catch (_) {
      // Best-effort — Discover remains the manual path.
    }
  }

  Future<void> _openDiscoveredForumHost(String forumHostUrl) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncSettingsScreen(
          db: widget.db,
          localDid: widget.did,
          initialForumHostUrl: forumHostUrl,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  void _selectBoard(String? boardId) {
    setState(() {
      _mobileNavigationVisible = true;
      _selectedBoardId = boardId;
      _feedFilter = boardId == null ? FeedFilter.all : FeedFilter.boards;
    });
    _loadData();
  }

  /// Opens a board's own page (its thread list, with in-board posting) instead
  /// of merely filtering the aggregate feed. Tapping a board in the sidebar /
  /// board sheet routes here; "All Activity" (a null id) still falls back to
  /// the filtered feed via [_selectBoard].
  Future<void> _openBoard(String boardId) async {
    Board? board;
    for (final b in _boards) {
      if (b.id == boardId) {
        board = b;
        break;
      }
    }
    if (board == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ThreadsListScreen(
          db: widget.db,
          board: board!,
          localDid: widget.did,
          opsDispatchService: _opsDispatchService,
          onFlushPendingOps: _flushPendingOps,
          // Follow the Forum board's Paper/Ink choice into the board detail.
          screenStyle: _screenStyles[ElixTab.circle] ?? ElixScreenStyle.paper,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  void _selectFeedFilter(FeedFilter filter) {
    setState(() {
      _feedFilter = filter;
      if (filter == FeedFilter.following || filter == FeedFilter.all) {
        _selectedBoardId = null;
      }
    });
    _loadData();
  }

  void _selectPersonalFilter(PersonalFilter filter) {
    setState(() => _personalFilter = filter);
  }

  static String _screenStyleKey(ElixTab tab) => 'elix-screen-style.${tab.name}';
  static const _boardMotionKey = 'elix-board-motion';

  Future<void> _loadScreenStyles() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _screenStyles = {
        for (final tab in ElixTab.values)
          tab: prefs.containsKey(_screenStyleKey(tab))
              ? ElixScreenStyleUi.fromStorage(
                  prefs.getString(_screenStyleKey(tab)),
                )
              : ElixScreenStyle.paper,
      };
    });
  }

  Future<void> _setScreenStyle(ElixTab tab, ElixScreenStyle screenStyle) async {
    setState(() {
      _screenStyles = {..._screenStyles, tab: screenStyle};
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_screenStyleKey(tab), screenStyle.storageValue);
  }

  Future<void> _loadBoardMotion() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_boardMotionKey);
    if (!mounted || saved == null) return;
    setState(() {
      _boardMotion = ElixBoardMotionUi.fromStorage(saved);
    });
  }

  Future<void> _setBoardMotion(ElixBoardMotion motion) async {
    setState(() => _boardMotion = motion);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_boardMotionKey, motion.storageValue);
  }

  void _handlePageChanged(int page) {
    final board = HomeBoard.values[page.clamp(0, HomeBoard.values.length - 1)];
    final tab = board == HomeBoard.forum ? ElixTab.circle : ElixTab.feed;
    if (_selectedBoard == board && _selectedTab == tab) return;
    setState(() {
      _mobileNavigationVisible = true;
      _selectedBoard = board;
      _selectedTab = tab;
    });
  }

  void _selectTab(ElixTab tab) {
    if (_selectedTab != tab) {
      setState(() {
        _mobileNavigationVisible = true;
        _selectedTab = tab;
      });
    }
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          tab.index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _selectBoardSwipe(HomeBoard board) {
    if (_selectedBoard != board) {
      setState(() {
        _mobileNavigationVisible = true;
        _selectedBoard = board;
        _selectedTab = board == HomeBoard.forum ? ElixTab.circle : ElixTab.feed;
      });
    }
    _syncPagerToBoard(board);
  }

  /// Move the boards pager onto [board]. When the pager is already mounted we
  /// animate; when it is not (e.g. returning to the boards from the in-shell
  /// 通知/我 destinations, which un-mount it and reset the controller to its
  /// initial page) we jump once it reattaches on the next frame.
  void _syncPagerToBoard(HomeBoard board) {
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          board.index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(board.index);
    });
  }

  Future<void> _checkCoachmark() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final shown = prefs.getBool('elix_board_swipe_shown') ?? false;
    if (!shown) setState(() => _showCoachmark = true);
  }

  Future<void> _dismissCoachmark() async {
    setState(() => _showCoachmark = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('elix_board_swipe_shown', true);
  }

  void _openCircleScreen(
    BuildContext context,
    CircleTab initialTab, {
    bool openNoteEditorOnStart = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CircleFullScreen(
          did: widget.did,
          db: widget.db,
          initialTab: initialTab,
          contentItems: _contentItems,
          contentItemRepository: _contentItemRepo,
          murmurReferenceCounts: _murmurReferenceCounts,
          onContentItemsChanged: _loadData,
          onPublishContentItem: _publishContentItem,
          onSummonAiForNote: _startAiTransformation,
          openNoteEditorOnStart: openNoteEditorOnStart,
        ),
      ),
    );
  }

  void _openScreenStyleSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ScreenStyleSheet(
        personalStyle: _screenStyles[ElixTab.feed] ?? ElixScreenStyle.paper,
        forumStyle: _screenStyles[ElixTab.circle] ?? ElixScreenStyle.paper,
        motion: _boardMotion,
        onPersonalStyleSelected: (style) =>
            unawaited(_setScreenStyle(ElixTab.feed, style)),
        onForumStyleSelected: (style) =>
            unawaited(_setScreenStyle(ElixTab.circle, style)),
        onMotionSelected: (motion) => unawaited(_setBoardMotion(motion)),
      ),
    );
  }

  void _openCompose(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 18),
              decoration: BoxDecoration(
                color: AnsibleDesign.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ComposeActionItem(
              icon: Icons.mic_outlined,
              title: context.uiCopy(zh: '碎念', en: 'Murmur'),
              subtitle: context.uiCopy(
                zh: 'MURMUR · 文字或語音',
                en: 'MURMUR · text or voice',
              ),
              onTap: () {
                Navigator.pop(context);
                _openCircleScreen(context, CircleTab.murmur);
              },
            ),
            const Divider(height: 0.5, color: AnsibleDesign.ruleSoft),
            ComposeActionItem(
              icon: Icons.edit_outlined,
              title: context.uiCopy(zh: '筆記', en: 'Note'),
              subtitle: context.uiCopy(
                zh: 'NOTE · 長文或想法',
                en: 'NOTE · long-form thought',
              ),
              onTap: () {
                Navigator.pop(context);
                _openCircleScreen(
                  context,
                  CircleTab.notes,
                  openNoteEditorOnStart: true,
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _selectCircleTab(CircleTab tab) {
    setState(() => _selectedCircleTab = tab);
  }

  Future<void> _startAiTransformation({
    String? noteId,
    String? noteTitle,
    String? noteBody,
  }) async {
    final providers = await _aiProviderConfigRepo.list();
    if (!mounted) return;

    // Build provider from first configured provider (if any)
    AiProvider? aiProvider;
    AiProviderType aiProviderType = AiProviderType.manual;
    if (providers.isNotEmpty) {
      final config = providers.first;
      aiProviderType = config.providerType;
      final apiKey = await _aiProviderConfigStore.readApiKey(config);
      if (!mounted) return;
      if (config.providerType == AiProviderType.manual) {
        aiProvider = ManualAiProvider();
      } else if (config.baseUrl != null && config.modelName != null) {
        aiProvider = OpenAiCompatibleProvider(
          baseUrl: Uri.parse(config.baseUrl!),
          model: config.modelName!,
          apiKey: apiKey ?? '',
        );
      }
    }

    if (aiProvider == null) {
      // No provider configured — show setup sheet first
      final result = await showModalBottomSheet<AiProviderSetupResult>(
        context: context,
        backgroundColor: AnsibleDesign.paper,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const AiProviderSetupSheet(),
      );
      if (result == null) return;
      final savedConfig = await _aiProviderConfigStore.save(
        displayName: result.displayName,
        providerType: result.providerType,
        baseUrl: result.baseUrl,
        modelName: result.modelName,
        apiKey: result.apiKey,
        defaultForTransformations: true,
        defaultForSummaries: true,
      );
      if (!mounted) return;
      if (savedConfig.providerType == AiProviderType.manual) {
        aiProviderType = savedConfig.providerType;
        aiProvider = ManualAiProvider();
      } else if (savedConfig.baseUrl != null && savedConfig.modelName != null) {
        aiProviderType = savedConfig.providerType;
        aiProvider = OpenAiCompatibleProvider(
          baseUrl: Uri.parse(savedConfig.baseUrl!),
          model: savedConfig.modelName!,
          apiKey: result.apiKey ?? '',
        );
      }
    }

    final resolvedProvider = aiProvider;
    if (resolvedProvider == null) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      showDragHandle: false,
      isScrollControlled: true,
      builder: (_) => AgentSheet(
        searchService: _vectorSearchService,
        authorDid: widget.did,
        contentItemRepo: _contentItemRepo,
        contentRelationRepo: _contentRelationRepo,
        aiProvider: resolvedProvider,
        aiProviderType: aiProviderType,
        noteId: noteId,
        noteTitle: noteTitle,
        noteBody: noteBody,
        onNoteUpdated: _loadData,
      ),
    );
  }

  // Following-feed source: the scalable AppView timeline when enabled+configured,
  // otherwise the local Design-1 filter over synced ops. (AppView mode currently
  // serves federated follows; localOnly follows via the local path is a planned
  // hybrid refinement.)
  FollowFeedSource _followFeedSource() {
    if (AppEnvironment.useAppViewFeed &&
        AppEnvironment.appViewBaseUrl.isNotEmpty) {
      final client = AppViewTimelineClient(
        baseUrl: AppEnvironment.appViewBaseUrl,
      );
      return AppViewTimelineSource(
        followRepository: _followRepo,
        fetcher: client.fetch,
        // Prefer the server-materialized home timeline (fan-out-on-write) when
        // enabled; otherwise fall back to fan-out-on-read over the follow set.
        homeFetcher: AppEnvironment.useAppViewHomeTimeline
            ? client.fetchHome
            : null,
      );
    }

    return LocalDeltaFilterSource(
      postProjector: FollowFeedProjector(
        followRepository: _followRepo,
        boardRepository: _boardRepo,
        threadRepository: _threadRepo,
        postRepository: _postRepo,
      ),
      contentProjector: ContentItemFeedProjector(
        followRepository: _followRepo,
        contentItemRepository: _contentItemRepo,
      ),
    );
  }

  /// Builds the social home wall. When online, newest verified public content
  /// fills a sparse following feed so a new account sees a real, changing wall
  /// instead of static onboarding copy. The combined wall stays chronological.
  Future<List<FollowTimelineItem>> _dynamicWallItems({int limit = 100}) async {
    final source = _followFeedSource();
    final followed = (await source.fetch(
      followerDid: widget.did,
      limit: limit,
    )).items;

    if (!AppEnvironment.useAppViewFeed ||
        AppEnvironment.appViewBaseUrl.isEmpty ||
        followed.length >= limit) {
      return followed;
    }

    try {
      final client = AppViewTimelineClient(
        baseUrl: AppEnvironment.appViewBaseUrl,
      );
      final page = await client.fetchExplore(limit: limit - followed.length);
      final mapper = AppViewTimelineSource(
        followRepository: _followRepo,
        fetcher: client.fetch,
      );
      final merged = <FollowTimelineItem>[...followed];
      final seen = followed.map(_timelineItemKey).toSet();
      for (final item in mapper.mapItems(page.items)) {
        if (seen.add(_timelineItemKey(item))) merged.add(item);
      }
      merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return merged.take(limit).toList(growable: false);
    } catch (_) {
      return followed;
    }
  }

  String _timelineItemKey(FollowTimelineItem item) => switch (item) {
    PostTimelineItem(:final entry) => 'post:${entry.thread.id}',
    ContentTimelineItem(:final entry) => 'content:${entry.item.id}',
  };

  List<PostCardData> _mergeDynamicWallCards(
    List<PostCardData> remote,
    List<PostCardData> local,
  ) {
    final merged = <PostCardData>[];
    final seen = <String>{};
    for (final card in [...remote, ...local]) {
      if (seen.add(card.thread.id)) merged.add(card);
    }
    merged.sort((a, b) => b.thread.updatedAt.compareTo(a.thread.updatedAt));
    return merged;
  }

  Future<List<PostCardData>> _buildFollowingPostCards(
    List<FollowTimelineItem> items,
    Map<String, Board> boardMap,
  ) async {
    final cards = <PostCardData>[];
    final l10n = context.l10n;
    for (final item in items) {
      if (item is ContentTimelineItem) {
        cards.add(
          _contentFollowCard(
            item.entry.item,
            signatureVerified: item.signatureVerified,
          ),
        );
        continue;
      }
      if (item is! PostTimelineItem) continue;
      final entry = item.entry;
      final posts = await _postRepo.list(threadId: entry.thread.id);
      final reactions = await _reactionRepo.listByTarget(
        store.TargetType.thread.name,
        entry.thread.id,
      );
      final countMap = <String, int>{};
      var reacted = false;
      for (final reaction in reactions) {
        countMap[reaction.reactionType.name] =
            (countMap[reaction.reactionType.name] ?? 0) + 1;
        if (reaction.userId == widget.did &&
            reaction.reactionType == store.ReactionType.thumbsUp) {
          reacted = true;
        }
      }
      final board = entry.board ?? boardMap[entry.post.boardId];
      cards.add(
        PostCardData(
          thread: entry.thread,
          category: board?.title ?? l10n.uncategorized,
          title: entry.thread.title,
          author: entry.post.authorId,
          board: board?.title ?? entry.post.boardId,
          timeAgo: _formatTimeAgo(entry.post.createdAt),
          content: entry.post.content,
          reactions: {'👍': countMap[store.ReactionType.thumbsUp.name] ?? 0},
          comments: replyCountForPosts(posts),
          reacted: reacted,
          openingPost: entry.post,
          signatureVerified: entry.post.signatureVerified,
        ),
      );
    }
    return cards;
  }

  /// Render a followed user's standalone murmur/note as a feed card. These have
  /// no board/thread, so a lightweight synthetic thread carries the card.
  PostCardData _contentFollowCard(ContentItem item, {bool? signatureVerified}) {
    final isNote = item.mode == ContentMode.note;
    final label = isNote ? 'NOTE' : 'MURMUR';
    final title = (item.title != null && item.title!.trim().isNotEmpty)
        ? item.title!
        : (isNote ? 'Note' : 'Murmur');
    return PostCardData(
      thread: Thread(
        id: item.id,
        boardId: '',
        title: title,
        authorId: item.authorDid,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      ),
      category: 'FOLLOWING · $label',
      title: title,
      author: item.authorDid,
      board: 'FOLLOWING · $label',
      timeAgo: _formatTimeAgo(item.publishedAt ?? item.createdAt),
      content: item.body,
      reactions: const {'👍': 0},
      comments: 0,
      reacted: false,
      signatureVerified: signatureVerified ?? item.signatureVerified,
      // Murmur/note have no thread — tapping must not open an empty thread view.
      openableThread: false,
    );
  }

  /// Seeds the default relay node (from the build's relay URL) when the local
  /// node list is empty, so a fresh install can sync without the user having to
  /// manually add a relay in Sync settings. Idempotent + best-effort.
  Future<void> _ensureDefaultRelayNode() async {
    if (!widget.autoSeedDefaultRelay) return;
    try {
      final url = AppEnvironment.defaultRelayBaseUrl.trim();
      if (url.isEmpty) return;
      final defaultOrigin = _relayOrigin(url);
      final host = Uri.tryParse(url)?.host ?? '';
      final name = host.isNotEmpty ? host.split('.').first : 'Elix Relay';
      final now = DateTime.now();

      final existing = await _remoteNodeRepo.list();
      // The build-provided dev/staging relay is public. Clear credentials left
      // behind by an older localhost node; sending an invalid optional Bearer
      // token makes the otherwise-public delta endpoint return 401.
      final matching = existing
          .where((n) => _relayOrigin(n.url) == defaultOrigin)
          .toList();
      if (matching.isNotEmpty) {
        for (final node in matching.where((n) => n.accessToken != null)) {
          await _remoteNodeRepo.update(
            _relayNodeWithoutToken(node, url: url, name: name, now: now),
          );
        }
        return;
      }

      // Self-heal build-provided endpoints. Staging/prod can never use a local
      // relay, but older builds accidentally seeded 127.0.0.1 because the
      // ANSIBLE_RELAY_BASE_URL define was missing. Re-point that entry without
      // deleting the app's local-first data. Custom non-local hosts are kept.
      final stale = existing.where((n) {
        final h = Uri.tryParse(n.url)?.host ?? '';
        final isLocal =
            h == 'localhost' ||
            h == '::1' ||
            h.startsWith('127.') ||
            h.endsWith('.localhost');
        return h.endsWith('.run.app') ||
            (AppEnvironment.name != AppEnvironmentName.dev && isLocal);
      }).toList();
      if (stale.isNotEmpty) {
        for (final node in stale) {
          await _remoteNodeRepo.update(
            _relayNodeWithoutToken(node, url: url, name: name, now: now),
          );
        }
        return;
      }

      // Non-empty with no default and no run.app node → leave the user's setup
      // alone. Only seed on a truly fresh install.
      if (existing.isNotEmpty) return;
      // Compliance-review gap #2: capture the host-declared compliance level
      // at seed time (best-effort).
      final discoveryClient = RelayDiscoveryClient(baseUrl: url);
      final compliance = await discoveryClient
          .fetchHostConstitutionCompliance();
      discoveryClient.close();
      await _remoteNodeRepo.create(
        RemoteNode(
          id: now.millisecondsSinceEpoch.toString(),
          name: name,
          url: url,
          createdAt: now,
          updatedAt: now,
          isActive: true,
          constitutionCompliance: compliance,
        ),
      );
    } catch (_) {
      // Best-effort; the user can still add a relay manually in Sync settings.
    }
  }

  RemoteNode _relayNodeWithoutToken(
    RemoteNode node, {
    required String url,
    required String name,
    required DateTime now,
  }) {
    return RemoteNode(
      id: node.id,
      name: name,
      url: url,
      syncCursor: node.syncCursor,
      lastSyncAt: node.lastSyncAt,
      createdAt: node.createdAt,
      updatedAt: now,
      isActive: node.isActive,
      constitutionCompliance: node.constitutionCompliance,
    );
  }

  /// scheme://host:port for comparing relay URLs regardless of path/trailing
  /// slash. Returns the lowercased input on parse failure.
  String _relayOrigin(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return url.trim().toLowerCase();
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port';
  }

  /// Best-effort: re-list the boards this DID created on each active forum host
  /// and rebuild the local board + projection + subscription for any that are
  /// missing. Board authorship is recorded host-side, but subscriptions are
  /// client-local — so after a reinstall the user would otherwise lose their own
  /// boards until manually re-subscribing via Discover.
  Future<void> _reconcileCreatedBoards() async {
    final did = widget.did;
    if (did.isEmpty) return;
    try {
      final hosts = (await _remoteNodeRepo.list())
          .where((node) => node.isActive)
          .toList();
      if (hosts.isEmpty) return;
      final existingLocalIds = (await _hostedBoardRepo.listProjections())
          .map((projection) => projection.localBoardId)
          .toSet();
      for (final host in hosts) {
        final client = ForumHostClient(baseUrl: host.url);
        try {
          final boards = await client.listBoardsCreatedBy(did);
          for (final board in boards) {
            final hostedBoardId = board['hosted_board_id'] as String?;
            if (hostedBoardId == null || hostedBoardId.isEmpty) continue;
            final localBoardId = '${host.id}_$hostedBoardId';
            if (existingLocalIds.contains(localBoardId)) continue;
            await _restoreHostedBoard(host.id, hostedBoardId, board);
            existingLocalIds.add(localBoardId);
          }
        } catch (_) {
          // Per-host best-effort; a relay-only node 404s here — ignore.
        } finally {
          client.close();
        }
      }
    } catch (_) {
      // Best-effort; the user can still re-subscribe via Discover.
    }
  }

  Future<void> _restoreHostedBoard(
    String forumHostId,
    String hostedBoardId,
    Map<String, dynamic> board,
  ) async {
    final now = DateTime.now();
    final localBoardId = '${forumHostId}_$hostedBoardId';
    final title = board['title'] as String? ?? hostedBoardId;
    final description = board['description'] as String?;
    final localBoard = Board(
      id: localBoardId,
      slug: localBoardId,
      title: title,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _boardRepo.create(localBoard);
    } catch (_) {
      // Board row may already exist from a partial restore; continue.
    }
    await _hostedBoardRepo.upsertProjection(
      HostedBoardProjection(
        localBoardId: localBoardId,
        forumHostId: forumHostId,
        hostedBoardId: hostedBoardId,
        canonicalBoardUri: board['canonical_board_uri'] as String? ?? '',
        remoteSlug: board['slug'] as String? ?? hostedBoardId,
        localSlug: localBoard.slug,
        title: title,
        description: description,
        permissions: Map<String, Object?>.from(
          board['permissions'] as Map? ?? const {'read': true, 'write': true},
        ),
        postingPolicy: Map<String, Object?>.from(
          board['posting_policy'] as Map? ?? const {},
        ),
        accessPolicy: Map<String, Object?>.from(
          board['access_policy'] as Map? ?? const {},
        ),
        accessPolicyVersion: board['access_policy_version'] as int? ?? 1,
        contentVisibility: board['content_visibility'] as String? ?? 'public',
        encryptionEpoch: board['encryption_epoch'] as int? ?? 0,
        encryptionState: board['encryption_state'] as String? ?? 'disabled',
        federationPolicy: Map<String, Object?>.from(
          board['federation_policy'] as Map? ?? const {'mode': 'enabled'},
        ),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _hostedBoardRepo.upsertSubscription(
      BoardSubscription(
        subscriptionId: localBoardId,
        forumHostId: forumHostId,
        hostedBoardId: hostedBoardId,
        localBoardId: localBoardId,
        readEnabled: true,
        writeEnabled: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Idempotently anchors the local DID + public key with the active relay so
  /// the relay accepts the user's ops (boards, follows, profile, content). The
  /// app otherwise only anchors at registration, so a relay with a fresh DB (or
  /// a newly-pointed relay) doesn't know this DID and rejects every publish with
  /// `unknown_did`. Best-effort — failures surface when the user takes an action.
  Future<void> _ensureAnchored() async {
    final did = widget.did;
    if (did.isEmpty) return;
    final relayUrl = AppEnvironment.atProtoBaseUrl;
    try {
      // Always attempt register+anchor rather than short-circuiting on a known
      // public key: a DID can be *verified* (public key on file, enough to
      // create a board) yet not *anchored* into the account store that
      // createRecord checks — so publishing 401s with unregistered_did. The
      // relay's anchor is idempotent (409 duplicate_did / handle_taken for an
      // already-anchored DID), so re-running is safe and heals that gap.
      final pubKeyHex =
          widget.publicKeyHex ?? (await DidManagerImpl().load())?.publicKeyHex;
      if (pubKeyHex == null || pubKeyHex.isEmpty) return;

      final suffix = _anchorHandleSuffix(did);
      final client = AtProtoClient(baseUrl: relayUrl);
      final challenge = await client.register(
        publicKeyHex: pubKeyHex,
        handleSuffix: suffix,
      );
      final sig = await DidSignerImpl().sign(utf8.encode(challenge.nonce));
      await client.anchor(
        AnchorRequest(
          did: did,
          publicKeyHex: pubKeyHex,
          handle: challenge.handle ?? '$suffix.elix.cool',
          registrationSig: sig.hex,
          nonce: challenge.nonce,
        ),
      );
    } catch (_) {
      // Best-effort; any failure is surfaced when the user performs an action.
    }
  }

  /// A relay handle suffix derived from the DID (alphanumeric, ≤20 chars). Only
  /// used to satisfy the relay's register/anchor handshake when re-anchoring.
  String _anchorHandleSuffix(String did) {
    final cleaned = did.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
    final tail = cleaned.length > 20
        ? cleaned.substring(cleaned.length - 20)
        : cleaned;
    return tail.isEmpty ? 'user' : tail;
  }

  Future<void> _createBoard() async {
    final forumHosts = (await _remoteNodeRepo.list())
        .where((node) => node.isActive)
        .toList();
    if (forumHosts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.addForumHostFirst)));
      return;
    }
    if (!mounted) return;
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) =>
          BoardFormDialog(forumHosts: forumHosts, requireForumHost: true),
    );
    if (result == null) return;
    final now = DateTime.now();
    final forumHostId = result['forumHostId'];
    final forumHost = forumHosts.firstWhere(
      (host) => host.id == forumHostId,
      orElse: () => forumHosts.first,
    );
    final title = result['title']!;
    final minPostTier = result['minPostTier'];
    final postingPolicy = minPostTier == null
        ? null
        : <String, Object?>{'min_post_tier': minPostTier};
    final accessPolicy = Map<String, Object?>.from(
      jsonDecode(result['accessPolicyJson']!) as Map,
    );
    final contentVisibility = result['contentVisibility']!;
    final federationPolicy = Map<String, Object?>.from(
      jsonDecode(result['federationPolicyJson']!) as Map,
    );
    final intentId = _uuid.v4();
    final createdAt = now.toUtc();
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final canonicalPayload = CreateHostedBoardIntent.canonicalPayload(
      intentId: intentId,
      authorDid: widget.did,
      targetForumHost: forumHost.url,
      title: title,
      description: result['description'],
      postingPolicy: postingPolicy,
      accessPolicy: accessPolicy,
      contentVisibility: contentVisibility,
      federationPolicy: federationPolicy,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
    try {
      final signature = await DidSignerImpl()
          .sign(utf8.encode(jsonEncode(canonicalPayload)))
          .then((signature) => signature.hex);
      final forumHostClient = ForumHostClient(baseUrl: forumHost.url);
      final Map<String, dynamic> remoteBoard;
      try {
        remoteBoard = await forumHostClient.createHostedBoard(
          CreateHostedBoardIntent(
            intentId: intentId,
            authorDid: widget.did,
            targetForumHost: forumHost.url,
            signature: signature,
            title: title,
            description: result['description'],
            postingPolicy: postingPolicy,
            accessPolicy: accessPolicy,
            contentVisibility: contentVisibility,
            federationPolicy: federationPolicy,
            createdAt: createdAt,
            expiresAt: expiresAt,
          ),
        );
      } finally {
        forumHostClient.close();
      }
      final hostedBoardId = remoteBoard['hosted_board_id'] as String;
      final localBoardId = '${forumHost.id}_$hostedBoardId';
      final remoteSlug = remoteBoard['slug'] as String? ?? _slugify(title);
      final slug = _uniqueLocalBoardSlug(remoteSlug, localBoardId);
      final board = Board(
        id: localBoardId,
        slug: slug.isEmpty ? localBoardId : slug,
        title: remoteBoard['title'] as String? ?? title,
        description:
            remoteBoard['description'] as String? ?? result['description'],
        createdAt: now,
        updatedAt: now,
      );
      await _boardRepo.create(board);
      await _hostedBoardRepo.upsertProjection(
        HostedBoardProjection(
          localBoardId: board.id,
          forumHostId: forumHost.id,
          hostedBoardId: hostedBoardId,
          canonicalBoardUri: remoteBoard['canonical_board_uri'] as String,
          remoteSlug: remoteSlug,
          localSlug: board.slug,
          title: board.title,
          description: board.description,
          permissions: Map<String, Object?>.from(
            remoteBoard['permissions'] as Map? ??
                const {'read': true, 'write': true},
          ),
          postingPolicy: Map<String, Object?>.from(
            remoteBoard['posting_policy'] as Map? ?? postingPolicy ?? const {},
          ),
          accessPolicy: Map<String, Object?>.from(
            remoteBoard['access_policy'] as Map? ?? accessPolicy,
          ),
          accessPolicyVersion:
              remoteBoard['access_policy_version'] as int? ?? 1,
          contentVisibility:
              remoteBoard['content_visibility'] as String? ?? contentVisibility,
          encryptionEpoch: remoteBoard['encryption_epoch'] as int? ?? 0,
          encryptionState:
              remoteBoard['encryption_state'] as String? ?? 'disabled',
          federationPolicy: Map<String, Object?>.from(
            remoteBoard['federation_policy'] as Map? ?? federationPolicy,
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _hostedBoardRepo.upsertSubscription(
        BoardSubscription(
          subscriptionId: '${forumHost.id}_$hostedBoardId',
          forumHostId: forumHost.id,
          hostedBoardId: hostedBoardId,
          localBoardId: board.id,
          readEnabled: true,
          writeEnabled: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(zh: '已建立看板「$title」', en: 'Board "$title" created'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(zh: '建立看板失敗：$e', en: 'Could not create board: $e'),
          ),
        ),
      );
    }
  }

  Future<void> _createThread() async {
    final dialogResult = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => ThreadComposerScreen(
          boards: _boards,
          initialBoardId: _selectedBoardId,
          authorDid: widget.did,
          db: widget.db,
        ),
      ),
    );
    if (dialogResult == null) return;
    final threadTitle = (dialogResult['title'] as String?)?.trim();
    final boardId = dialogResult['boardId'] as String?;
    final content = (dialogResult['content'] as String?)?.trim() ?? '';
    final crossPostTargetIds =
        (dialogResult['crossPostTargetIds'] as List?)?.cast<String>() ??
        const <String>[];
    if (threadTitle == null ||
        threadTitle.isEmpty ||
        boardId == null ||
        boardId.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final thread = Thread(
      id: _uuid.v4(),
      boardId: boardId,
      title: threadTitle,
      authorId: widget.did,
      createdAt: now,
      updatedAt: now,
    );
    final projection = await _hostedBoardRepo.getProjectionByLocalBoardId(
      boardId,
    );
    await _threadRepo.create(thread);
    await _enqueueAndFlush(
      projection?.contentVisibility == 'end_to_end_encrypted'
          ? await PrivateBoardOpFactory().createThread(
              board: projection!,
              authorDid: widget.did,
              entityId: thread.id,
              title: thread.title,
              createdAt: now,
            )
          : CrdtOpBuilder.createThread(
              authorDid: widget.did,
              entityId: thread.id,
              boardId: boardId,
              title: thread.title,
            ),
    );
    // 建立首帖
    final post = Post(
      id: _uuid.v4(),
      threadId: thread.id,
      boardId: boardId,
      authorId: widget.did,
      content: content,
      createdAt: now,
      updatedAt: now,
      lastEditAt: now,
      parentPostId: null,
      signatureVerified: true, // signed locally via the ops dispatch below
    );
    await _postRepo.create(post);
    await _enqueueAndFlush(
      projection?.contentVisibility == 'end_to_end_encrypted'
          ? await PrivateBoardOpFactory().createPost(
              board: projection!,
              authorDid: widget.did,
              entityId: post.id,
              threadId: thread.id,
              content: post.content,
              createdAt: now,
            )
          : CrdtOpBuilder.createPost(
              authorDid: widget.did,
              entityId: post.id,
              boardId: boardId,
              threadId: thread.id,
              content: post.content,
            ),
    );
    await _recordThreadPublicationTargets(
      threadId: thread.id,
      boardId: boardId,
      crossPostTargetIds: crossPostTargetIds,
    );
    await _loadData();
  }

  /// Records hosted-board publication targets for a new thread (primary +
  /// selected cross-posts) and surfaces a non-blocking notice when some
  /// cross-post targets were rejected. Never blocks the primary publication.
  Future<void> _recordThreadPublicationTargets({
    required String threadId,
    required String boardId,
    required List<String> crossPostTargetIds,
  }) async {
    final service = ForumPublicationService(hostedBoards: _hostedBoardRepo);
    final result = await service.createThreadForLocalBoard(
      localDraftId: threadId,
      primaryLocalBoardId: boardId,
      crossPostTargetIds: crossPostTargetIds,
    );
    if (result == null) return;
    final failedCrossPosts = result.rejectedTargetIds
        .where(crossPostTargetIds.contains)
        .toList();
    if (failedCrossPosts.isEmpty) return;
    final titles = await service.boardTitlesForTargets(
      _boardRepo,
      failedCrossPosts,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '部分看板未能同時發佈：${titles.join('、')}',
            en: 'Could not cross-post to: ${titles.join(', ')}',
          ),
        ),
      ),
    );
  }

  Future<void> _enqueueAndFlush(OpsQueueEntry entry) async {
    await _opsDispatchService.signAndEnqueue(entry);
    unawaited(_flushPendingOps());
  }

  Future<void> _publishContentItem(
    ContentItem item,
    DistributionPreference distributionPreference,
  ) async {
    final result = await ContentPublicationService(
      contentItems: _contentItemRepo,
      publications: _publicationRepo,
      relaySettings: _nostrRelaySettingsStore,
      remoteNodes: _remoteNodeRepo,
      keyStore: _nostrKeyStore,
      signingBridge: const SchnorrSigningBridge(),
    ).publishContentItem(item, distributionPreference: distributionPreference);
    if (!mounted) return;
    if (result.published > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.syncedPublicCount(result.published)),
        ),
      );
    } else if (result.failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.publicQueuedRelayFailed)),
      );
    } else if (result.skippedReason == 'no_write_relays') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noWritableNostrRelay)),
      );
    }
  }

  Future<void> _flushPendingOps() async {
    final activeNode = await _remoteNodeRepo.getActive();
    final service = activeNode == null
        ? _opsDispatchService
        : OpsDispatchService(
            repository: _opsQueueRepo,
            relayClient: RelayOpsClient(baseUrl: activeNode.url),
          );
    await service.flushPending();
  }

  AppSyncService _appSyncService() {
    final boardAccess = BoardAccessPresentationService(
      walletRepository: DriftWalletRepository(widget.db),
    );
    final boardCapabilities = <String, BoardAccessCapability>{};
    final preparedPrivateBoards = <String>{};
    final privateCrypto = PrivateBoardCryptoService();
    Future<Map<String, String>> authorizeBoard(
      HostedBoardProjection board,
      Uri requestUri,
      String action,
      String method,
    ) async {
      final cacheKey = '${board.hostedBoardId}:$action';
      var capability = boardCapabilities[cacheKey];
      if (capability == null ||
          capability.policyVersion != board.accessPolicyVersion ||
          !capability.expiresAt.isAfter(
            DateTime.now().toUtc().add(const Duration(seconds: 5)),
          )) {
        capability = await boardAccess.authorize(
          forumHost: requestUri.replace(path: '', query: null, fragment: null),
          boardId: board.hostedBoardId,
          action: action,
        );
        boardCapabilities[cacheKey] = capability;
      }
      final privateKey =
          '${board.hostedBoardId}:${board.encryptionEpoch}:${board.accessPolicyVersion}';
      if (action == 'read' &&
          board.contentVisibility == 'end_to_end_encrypted' &&
          !preparedPrivateBoards.contains(privateKey)) {
        final host = requestUri.replace(path: '', query: null, fragment: null);
        final keyClient = PrivateBoardKeyClient(
          forumHost: host,
          boardId: board.hostedBoardId,
          access: boardAccess,
        );
        final publicKey = await privateCrypto.ensureDeviceKey(
          board.hostedBoardId,
        );
        await keyClient.registerDevice(
          capability: capability,
          publicKeyHex: publicKey.publicKeyHex,
        );
        final envelope = await keyClient.currentEnvelope(
          capability: capability,
        );
        if (envelope.epoch != board.encryptionEpoch ||
            envelope.policyVersion != board.accessPolicyVersion) {
          throw const PrivateBoardCryptoException('stale_epoch_envelope');
        }
        await privateCrypto.unwrapEpochKey(envelope);
        preparedPrivateBoards.add(privateKey);
      }
      return boardAccess.proofHeaders(
        capability: capability,
        method: method,
        requestUri: requestUri,
        scope: action,
      );
    }

    return AppSyncService(
      remoteNodeRepo: _remoteNodeRepo,
      boardSyncConfigRepo: DriftBoardSyncConfigRepository(widget.db),
      hostedBoardRepo: DriftHostedBoardRepository(widget.db),
      boardRepo: _boardRepo,
      threadRepo: _threadRepo,
      postRepo: _postRepo,
      contentItemRepo: _contentItemRepo,
      publicationRepo: _publicationRepo,
      relaySettings: _nostrRelaySettingsStore,
      keyStore: _nostrKeyStore,
      followRepository: _followRepo,
      contactRepository: _contactRepo,
      didReputationRepo: _didReputationRepo,
      followerDid: widget.did,
      notificationProjector: _notificationProjector,
      hostModerationSync: HostModerationSyncService(
        moderationRepo: store.DriftHostModerationStateRepository(widget.db),
        hostedBoardRepo: _hostedBoardRepo,
        threadRepo: _threadRepo,
        postRepo: _postRepo,
        notificationProjector: _notificationProjector,
        localDid: widget.did,
      ),
      remoteTombstoneRepository: DriftRemoteTombstoneRepository(widget.db),
      opsQueueRepo: _opsQueueRepo,
      opsDispatchService: _opsDispatchService,
      signingBridge: const SchnorrSigningBridge(),
      reputationPresentationService: RelayReputationPresentationService(
        walletRepository: DriftWalletRepository(widget.db),
        reputationRepository: _didReputationRepo,
      ),
      syncCapabilityService: (node) =>
          SyncCapabilityService(baseUrl: node.url, holderDid: widget.did),
      authorizeBoardRead: (board, requestUri) =>
          authorizeBoard(board, requestUri, 'read', 'GET'),
      authorizeBoardWrite: (board, requestUri) =>
          authorizeBoard(board, requestUri, 'post', 'POST'),
    );
  }

  /// Badge truth is local: the unread count comes from the device's
  /// notifications table, never a server.
  Future<void> _refreshNotificationUnread() async {
    final count = await _notificationRepo.unreadCount();
    if (!mounted || count == _notificationUnreadCount) return;
    setState(() => _notificationUnreadCount = count);
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _buildNotifications(embedded: false)),
    );
    await _refreshNotificationUnread();
  }

  /// Notifications content, reused by the wide push and the compact 通知
  /// destination ([embedded] true — no back chrome, the bottom nav switches).
  Widget _buildNotifications({required bool embedded}) {
    return NotificationsScreen(
      db: widget.db,
      did: widget.did,
      embedded: embedded,
      messengerService: _messengerSyncService,
    );
  }

  /// Settings content. The compact 我 destination uses [embedded] true (no back
  /// chrome — the bottom nav switches away); wide layouts that push it as a
  /// route pass false.
  Widget _buildSettings({required bool embedded}) {
    return SettingsHomeScreen(
      db: widget.db,
      did: widget.did,
      embedded: embedded,
      localeController: widget.localeController,
      readingPreferencesController: widget.readingPreferencesController,
      onClearIdentity: widget.onClearIdentity,
      personalScreenStyle: _screenStyles[ElixTab.feed] ?? ElixScreenStyle.paper,
      forumScreenStyle: _screenStyles[ElixTab.circle] ?? ElixScreenStyle.paper,
      boardMotion: _boardMotion,
      onPersonalScreenStyleChanged: (style) =>
          unawaited(_setScreenStyle(ElixTab.feed, style)),
      onForumScreenStyleChanged: (style) =>
          unawaited(_setScreenStyle(ElixTab.circle, style)),
      onBoardMotionChanged: (motion) => unawaited(_setBoardMotion(motion)),
      onOpenPersonalBoard: () {
        // Leave the in-shell settings panel for the boards pager.
        setState(() => _dest = _ShellDest.board);
        _selectBoardSwipe(HomeBoard.personal);
      },
    );
  }

  void _handleNetworkStatusChanged() {
    final current = _networkStatusService.status;
    final wasOnline = _lastNetworkStatus == NetworkStatus.online;
    _lastNetworkStatus = current;
    if (current != NetworkStatus.online || wasOnline) return;
    unawaited(_runAutoSyncIfConfigured());
  }

  Future<void> _runAutoSyncIfConfigured() async {
    if (_syncing) return;
    final now = DateTime.now();
    final last = _lastAutoSyncAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    if (!await _hasConfiguredSyncTargets()) return;
    _lastAutoSyncAt = now;
    await _runForegroundPullIfConfigured();
    await _runHeaderSync(showSnackBar: false, pullRemote: false);
  }

  Future<void> _runForegroundPullIfConfigured() async {
    if (_pullRefreshing || _syncing) return;
    if (_networkStatusService.status != NetworkStatus.online) return;
    if (!await _hasActiveRelay()) return;
    _pullRefreshing = true;
    try {
      final runner = widget.pullRefreshRunner;
      final result = runner == null
          ? await _appSyncService().pullLatestFromRelays()
          : await runner();
      if (result.pulledActivities > 0) {
        await _loadData();
      }
    } finally {
      _pullRefreshing = false;
    }
  }

  Future<bool> _hasActiveRelay() async {
    final nodes = await _remoteNodeRepo.list();
    return nodes.any((node) => node.isActive);
  }

  Future<bool> _hasConfiguredSyncTargets() async {
    final nodes = await _remoteNodeRepo.list();
    if (nodes.any((node) => node.isActive)) return true;
    final relays = await _nostrRelaySettingsStore.list();
    return relays.any((relay) => relay.write);
  }

  Future<void> _runHeaderSync({
    bool showSnackBar = true,
    bool pullRemote = true,
  }) async {
    if (_syncing) return;
    if (showSnackBar &&
        widget.syncRunner == null &&
        !await _hasConfiguredSyncTargets()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SubpageL10n.of(context).t('configureSyncTargets')),
        ),
      );
      return;
    }
    if (showSnackBar) {
      if (!mounted) return;
      final verifier = widget.userPresenceVerifier;
      final authenticationReason = context.uiCopy(
        zh: '請驗證裝置持有人，以同步並簽署待上傳的資料。',
        en: 'Authenticate to sync and sign pending uploads.',
      );
      final authenticated = verifier == null && widget.syncRunner != null
          ? true
          : await (verifier ?? LocalDeviceUserPresenceVerifier()).verify(
              reason: authenticationReason,
            );
      if (!authenticated) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.uiCopy(
                zh: '未完成裝置驗證，同步已取消；本機資料未變更。',
                en: 'Device authentication was not completed. Sync was cancelled and local data was unchanged.',
              ),
            ),
          ),
        );
        return;
      }
    }
    setState(() => _syncing = true);
    try {
      final runner = widget.syncRunner;
      final result = runner == null
          ? await _appSyncService().syncAll(
              pullRemote: pullRemote,
              pushLocal: showSnackBar,
            )
          : await runner();
      await _loadData();
      if (!mounted) return;
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appSyncSummaryMessage(result)),
            backgroundColor: result.success ? null : Colors.red,
          ),
        );
      }
    } catch (error) {
      if (!mounted || !showSnackBar) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.syncFailedMessage(error.toString())),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  /// Opens the network DiscoverScreen so the user can find + subscribe to
  /// boards (討論區). Constructed exactly like the top-bar / Timeline entries
  /// (same deps, no onOpenBoard → board rows use DiscoverScreen's built-in
  /// subscribe flow). Reloads on return so newly-followed boards show up.
  Future<void> _openDiscover() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoverScreen(
          db: widget.db,
          localDid: widget.did,
          client: DiscoveryClient(
            appViewBaseUrl: AppEnvironment.appViewBaseUrl,
            relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _openManageBoards() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = context.l10n;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(l10n.manageBoards),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hosted-board management (boards this DID created on a
                    // Forum Host) — distinct from the local/subscription list
                    // below, which stays the unsubscribe/rename surface.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.dashboard_customize_outlined),
                      title: Text(
                        context.uiCopy(zh: '我主持的看板', en: 'Boards I host'),
                      ),
                      subtitle: Text(
                        context.uiCopy(
                          zh: '編輯你建立的託管看板',
                          en: 'Edit the hosted boards you created',
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        _openHostedBoards();
                      },
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Flexible(child: _buildManageBoardsList(setStateDialog)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.close),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _createBoard();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addBoard),
                ),
              ],
            );
          },
        );
      },
    );
    await _loadData();
  }

  /// Pushes the "boards I host" management screen (hosted boards this DID
  /// created; edits go through signed update_board intents).
  Future<void> _openHostedBoards() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostedBoardsScreen(
          db: widget.db,
          did: widget.did,
          remoteNodeRepo: _remoteNodeRepo,
          hostedBoardRepo: _hostedBoardRepo,
          boardRepo: _boardRepo,
          onCreateBoard: _createBoard,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  Widget _buildManageBoardsList(StateSetter setStateDialog) {
    final l10n = context.l10n;
    return _boards.isEmpty
        ? Text(l10n.noBoardsYet)
        : ListView.separated(
            shrinkWrap: true,
            itemCount: _boards.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final board = _boards[index];
              return ListTile(
                title: Text(board.title),
                subtitle: board.description != null
                    ? Text(board.description!)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final result = await showDialog<Map<String, String?>>(
                          context: context,
                          builder: (context) => BoardFormDialog(
                            initialTitle: board.title,
                            initialDescription: board.description,
                          ),
                        );
                        if (result != null) {
                          final now = DateTime.now();
                          final updatedSlug = _slugify(
                            result['title'] ?? board.title,
                          );
                          final uniqueUpdatedSlug = updatedSlug.isEmpty
                              ? board.slug
                              : _uniqueLocalBoardSlug(updatedSlug, board.id);
                          final updated = Board(
                            id: board.id,
                            slug: uniqueUpdatedSlug,
                            title: result['title'] ?? board.title,
                            description: result['description'],
                            createdAt: board.createdAt,
                            updatedAt: now,
                            isDeleted: board.isDeleted,
                          );
                          await _boardRepo.update(updated);
                          await _loadData();
                          setStateDialog(() {});
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.deleteBoard),
                            content: Text(l10n.deleteBoardConfirm(board.title)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(l10n.cancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: Text(l10n.delete),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _boardRepo.delete(board.id);
                          // Also drop the hosted subscription so the
                          // board is truly unsubscribed (no resync).
                          await _hostedBoardRepo.removeForLocalBoard(board.id);
                          await _loadData();
                          setStateDialog(() {});
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
  }

  String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  String _uniqueLocalBoardSlug(String desiredSlug, String boardId) {
    final base = desiredSlug.trim().isEmpty ? boardId : desiredSlug.trim();
    final usedByOtherId = {
      for (final board in _boards)
        if (board.id != boardId) board.slug,
    };
    if (!usedByOtherId.contains(base)) return base;

    var candidate = base;
    var attempt = 2;
    do {
      candidate = '$base-$attempt';
      attempt += 1;
    } while (usedByOtherId.contains(candidate));
    return candidate;
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    final l10n = context.l10n;
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.hoursAgo(diff.inHours);
    return l10n.daysAgo(diff.inDays);
  }

  bool _handleCompactScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    bool? shouldShow;
    if (notification.metrics.pixels <= 8) {
      shouldShow = true;
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null && delta.abs() >= 0.5) {
        // Positive delta means the viewport advances into newer content: make
        // room for reading. Negative delta means the user is returning toward
        // the top: reveal navigation immediately.
        shouldShow = delta < 0;
      }
    } else if (notification is OverscrollNotification) {
      if (notification.overscroll < 0) shouldShow = true;
    }

    if (shouldShow == null) return false;
    final desiredVisibility = shouldShow;
    if (desiredVisibility != _mobileNavigationVisible) {
      setState(() => _mobileNavigationVisible = desiredVisibility);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentScreenStyle =
        (_screenStyles[_selectedTab] ?? ElixScreenStyle.paper).dataFor(
          Theme.of(context).brightness,
        );
    // Phone layout uses the bottom icon nav (Threads-style); wide keeps the
    // sidebar + top header.
    final compactShell = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      bottomNavigationBar: compactShell
          ? AutoHidingHomeBottomBar(
              visible: _mobileNavigationVisible,
              child: HomeBottomBar(
                selectedBoard: _selectedBoard,
                boardActive: _dest == _ShellDest.board,
                notificationsActive: _dest == _ShellDest.notifications,
                meActive: _dest == _ShellDest.me,
                onSelectBoard: (board) {
                  setState(() {
                    _mobileNavigationVisible = true;
                    _dest = _ShellDest.board;
                  });
                  _selectBoardSwipe(board);
                },
                onCompose: () => _selectedBoard == HomeBoard.forum
                    ? _createThread()
                    : _openCompose(context),
                onNotifications: () {
                  setState(() {
                    _mobileNavigationVisible = true;
                    _dest = _ShellDest.notifications;
                  });
                  unawaited(_refreshNotificationUnread());
                },
                onProfile: () => setState(() {
                  _mobileNavigationVisible = true;
                  _dest = _ShellDest.me;
                }),
                unreadCount: _notificationUnreadCount,
              ),
            )
          : null,
      body: SafeArea(
        child: Container(
          color: currentScreenStyle.background,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final mainPanel = MainPanel(
                db: widget.db,
                did: widget.did,
                localeController: widget.localeController,
                readingPreferencesController:
                    widget.readingPreferencesController,
                opsQueueRepo: _opsQueueRepo,
                opsDispatchService: _opsDispatchService,
                messengerSyncService: _messengerSyncService,
                contactAvailabilityResolver:
                    _messengerContactResolver.resolveAvailability,
                contactInputResolver: _contactResolver.resolveInput,
                hasActiveRelay: _hasActiveMessengerRelay,
                showFirstRunDiscovery: _showFirstRunDiscovery,
                firstRunDiscovery: _relayDiscovery,
                firstRunDiscoveryLoading: _relayDiscoveryLoading,
                onOpenDiscoveredForumHost: _openDiscoveredForumHost,
                onFlushPendingOps: _flushPendingOps,
                onSync: () => _runHeaderSync(),
                syncing: _syncing,
                notificationUnreadCount: _notificationUnreadCount,
                onOpenNotifications: _openNotifications,
                atProtoClient: _atProtoClient,
                onClearIdentity: widget.onClearIdentity,
                loading: _loading,
                posts: _posts,
                followingPosts: _followingPosts,
                onRefresh: _loadData,
                onCreateThread: _createThread,
                onCreateBoard: _createBoard,
                onManageBoards: _openManageBoards,
                onDiscoverBoards: _openDiscover,
                onOpenBoard: _openBoard,
                bottomNav: compactShell,
                onOpenBoards: compact ? () => _openBoardsSheet(context) : null,
                feedFilter: _feedFilter,
                onFeedFilterChanged: _selectFeedFilter,
                personalFilter: _personalFilter,
                onPersonalFilterChanged: _selectPersonalFilter,
                hasSelectedBoard: _selectedBoardId != null,
                selectedBoardId: _selectedBoardId,
                boards: _boards,
                networkStatusService: _networkStatusService,
                pageController: _pageController,
                selectedTab: _selectedBoard == HomeBoard.personal
                    ? ElixTab.feed
                    : ElixTab.circle,
                onTabChanged: _selectTab,
                onPageChanged: _handlePageChanged,
                selectedBoard: _selectedBoard,
                onBoardChanged: _selectBoardSwipe,
                showCoachmark: _showCoachmark,
                onDismissCoachmark: _dismissCoachmark,
                onOpenCircle: (ctx, tab) => _openCircleScreen(ctx, tab),
                onComposeTap: () => _openCompose(context),
                onScreenStyleTap: () => _openScreenStyleSheet(context),
                onPersonalScreenStyleChanged: (style) =>
                    unawaited(_setScreenStyle(ElixTab.feed, style)),
                onForumScreenStyleChanged: (style) =>
                    unawaited(_setScreenStyle(ElixTab.circle, style)),
                onBoardMotionChanged: (motion) =>
                    unawaited(_setBoardMotion(motion)),
                screenStyles: _screenStyles,
                boardMotion: _boardMotion,
                selectedCircleTab: _selectedCircleTab,
                onCircleTabChanged: _selectCircleTab,
                contentItemRepository: _contentItemRepo,
                contentItems: _contentItems,
                murmurReferenceCounts: _murmurReferenceCounts,
                onContentItemsChanged: _loadData,
                onPublishContentItem: _publishContentItem,
                onStartAiAction: _startAiTransformation,
                onSummonAiForNote: ({noteId, noteTitle, noteBody}) =>
                    _startAiTransformation(
                      noteId: noteId,
                      noteTitle: noteTitle,
                      noteBody: noteBody,
                    ),
              );

              if (compact) {
                // In-shell destinations keep the bottom nav mounted.
                final destination = switch (_dest) {
                  _ShellDest.notifications => _buildNotifications(
                    embedded: true,
                  ),
                  _ShellDest.me => _buildSettings(embedded: true),
                  _ShellDest.board => mainPanel,
                };
                return NotificationListener<ScrollNotification>(
                  onNotification: _handleCompactScroll,
                  child: destination,
                );
              }

              return Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: HomeSidebar(
                      boards: _boards,
                      selectedBoardId: _selectedBoardId,
                      onSelectBoard: (boardId) {
                        if (boardId == null) {
                          _selectBoard(null);
                        } else {
                          _openBoard(boardId);
                        }
                      },
                      onManageBoards: _loadData,
                    ),
                  ),
                  Expanded(child: mainPanel),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openBoardsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.72,
            child: HomeSidebar(
              boards: _boards,
              selectedBoardId: _selectedBoardId,
              onSelectBoard: (boardId) {
                Navigator.of(sheetContext).pop();
                if (boardId == null) {
                  _selectBoard(null);
                } else {
                  _openBoard(boardId);
                }
              },
              onManageBoards: () {
                Navigator.of(sheetContext).pop();
                _openManageBoards();
              },
            ),
          ),
        );
      },
    );
  }
}
