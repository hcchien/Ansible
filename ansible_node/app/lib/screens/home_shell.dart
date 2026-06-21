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
import '../services/host_moderation_sync_service.dart';
import '../services/nostr_relay_settings_store.dart';
import '../services/nostr_secure_key_store.dart';
import '../services/notification_preferences_controller.dart';
import '../services/notification_projector.dart';
import '../services/relay_discovery_client.dart';
import '../services/reading_preferences_controller.dart';
import '../services/relay_ops_client.dart';
import '../widgets/ai_provider_setup_sheet.dart';
import '../widgets/feed_filter_tabs.dart';
import 'notifications_screen.dart';
import 'sync_settings_screen.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import 'discover_screen.dart';
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
    this.networkStatusMonitor,
    this.localeController,
    this.readingPreferencesController,
    this.autoSeedDefaultRelay = true,
  });

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
  final NetworkStatusMonitor? networkStatusMonitor;
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
  int _notificationUnreadCount = 0;
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
  HomeBoard _selectedBoard = HomeBoard.personal;
  ElixBoardMotion _boardMotion = ElixBoardMotion.book;
  bool _showCoachmark = false;
  CircleTab _selectedCircleTab = CircleTab.murmur;
  late final PageController _pageController;
  Map<ElixTab, ElixScreenStyle> _screenStyles = {
    for (final tab in ElixTab.values)
      tab: tab == ElixTab.feed ? ElixScreenStyle.ink : ElixScreenStyle.paper,
  };
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
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
      // Re-list boards this DID created on its forum hosts and rebuild any
      // missing local subscriptions (e.g. after a reinstall wiped the local
      // DB), then refresh so they appear without a manual re-subscribe.
      unawaited(
        _reconcileCreatedBoards().whenComplete(() {
          if (mounted) unawaited(_loadData());
        }),
      );
      // Make sure our DID is anchored on the relay before publishing anything,
      // otherwise the relay rejects boards/follows/profile/content as unknown_did.
      unawaited(
        _ensureAnchored().whenComplete(() {
          if (mounted) unawaited(_runForegroundPullIfConfigured());
        }),
      );
      unawaited(_murmurIndexingService.indexAllPending());
      unawaited(_checkCoachmark());
    });
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
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    unawaited(_refreshNotificationUnread());
    final l10n = context.l10n;
    await ContactSourceSyncService(
      followRepository: _followRepo,
      contactRepository: _contactRepo,
      messengerRepository: _messengerRepo,
    ).syncForIdentity(widget.did);
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
        postCounts[t.id] = posts.length;

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
        signatureVerified: firstPosts[t.id]?.signatureVerified ?? false,
      );
    }).toList();

    // Timeline board (時間軸): posts from people you follow. Best-effort — a
    // discovery/AppView outage just yields an empty timeline, never an error.
    List<PostCardData> followingCards = const [];
    try {
      final followingEntries = (await _followFeedSource().fetch(
        followerDid: widget.did,
        limit: 100,
      )).items;
      followingCards = await _buildFollowingPostCards(
        followingEntries,
        boardMap,
      );
    } catch (_) {
      followingCards = const [];
    }

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

  Future<void> _openDiscoveredForumHost(String forumHostUrl) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncSettingsScreen(
          db: widget.db,
          initialForumHostUrl: forumHostUrl,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  void _selectBoard(String? boardId) {
    setState(() {
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
              : tab == ElixTab.feed
              ? ElixScreenStyle.ink
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
      _selectedBoard = board;
      _selectedTab = tab;
    });
  }

  void _selectTab(ElixTab tab) {
    if (_selectedTab != tab) {
      setState(() => _selectedTab = tab);
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
        _selectedBoard = board;
        _selectedTab = board == HomeBoard.forum ? ElixTab.circle : ElixTab.feed;
      });
    }
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          board.index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
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
        personalStyle: _screenStyles[ElixTab.feed] ?? ElixScreenStyle.ink,
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

  Future<List<PostCardData>> _buildFollowingPostCards(
    List<FollowTimelineItem> items,
    Map<String, Board> boardMap,
  ) async {
    final cards = <PostCardData>[];
    final l10n = context.l10n;
    for (final item in items) {
      if (item is ContentTimelineItem) {
        cards.add(_contentFollowCard(item.entry.item));
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
          comments: posts.length,
          reacted: reacted,
          signatureVerified: entry.post.signatureVerified,
        ),
      );
    }
    return cards;
  }

  /// Render a followed user's standalone murmur/note as a feed card. These have
  /// no board/thread, so a lightweight synthetic thread carries the card.
  PostCardData _contentFollowCard(ContentItem item) {
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
      // Already pointed at this build's relay → nothing to do.
      if (existing.any((n) => _relayOrigin(n.url) == defaultOrigin)) return;

      // Self-heal: an earlier build auto-seeded the relay's Cloud Run native
      // URL (*.run.app). Re-point that node at this build's relay rather than
      // leaving a stale/duplicate. Only rewrites run.app hosts — never a user's
      // custom forum host.
      final stale = existing.where((n) {
        final h = Uri.tryParse(n.url)?.host ?? '';
        return h.endsWith('.run.app');
      }).toList();
      if (stale.isNotEmpty) {
        for (final node in stale) {
          await _remoteNodeRepo.update(
            node.copyWith(url: url, name: name, updatedAt: now),
          );
        }
        return;
      }

      // Non-empty with no default and no run.app node → leave the user's setup
      // alone. Only seed on a truly fresh install.
      if (existing.isNotEmpty) return;
      await _remoteNodeRepo.create(
        RemoteNode(
          id: now.millisecondsSinceEpoch.toString(),
          name: name,
          url: url,
          createdAt: now,
          updatedAt: now,
          isActive: true,
        ),
      );
    } catch (_) {
      // Best-effort; the user can still add a relay manually in Sync settings.
    }
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
    final dialogResult = await Navigator.of(context).push<Map<String, String?>>(
      MaterialPageRoute(
        builder: (_) => ThreadComposerScreen(
          boards: _boards,
          initialBoardId: _selectedBoardId,
          authorDid: widget.did,
        ),
      ),
    );
    if (dialogResult == null) return;
    final threadTitle = dialogResult['title']?.trim();
    final boardId = dialogResult['boardId'];
    final content = dialogResult['content']?.trim() ?? '';
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
    await _threadRepo.create(thread);
    await _enqueueAndFlush(
      CrdtOpBuilder.createThread(
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
      CrdtOpBuilder.createPost(
        authorDid: widget.did,
        entityId: post.id,
        boardId: boardId,
        threadId: thread.id,
        content: post.content,
      ),
    );
    await _loadData();
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
      opsQueueRepo: _opsQueueRepo,
      opsDispatchService: _opsDispatchService,
      signingBridge: const SchnorrSigningBridge(),
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
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(db: widget.db, did: widget.did),
      ),
    );
    await _refreshNotificationUnread();
  }

  /// Opens Settings (the bottom bar's 我 destination on compact layouts).
  /// Mirrors the push the board-swipe header used in wide layouts.
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsHomeScreen(
          db: widget.db,
          did: widget.did,
          localeController: widget.localeController,
          readingPreferencesController: widget.readingPreferencesController,
          onClearIdentity: widget.onClearIdentity,
          personalScreenStyle:
              _screenStyles[ElixTab.feed] ?? ElixScreenStyle.ink,
          forumScreenStyle:
              _screenStyles[ElixTab.circle] ?? ElixScreenStyle.paper,
          boardMotion: _boardMotion,
          onPersonalScreenStyleChanged: (style) =>
              unawaited(_setScreenStyle(ElixTab.feed, style)),
          onForumScreenStyleChanged: (style) =>
              unawaited(_setScreenStyle(ElixTab.circle, style)),
          onBoardMotionChanged: (motion) =>
              unawaited(_setBoardMotion(motion)),
          onOpenPersonalBoard: () => _selectBoardSwipe(HomeBoard.personal),
        ),
      ),
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
    setState(() => _syncing = true);
    try {
      await _flushPendingOps();
      final runner = widget.syncRunner;
      final result = runner == null
          ? await _appSyncService().syncAll(pullRemote: pullRemote)
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
                child: _boards.isEmpty
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
                                    final result =
                                        await showDialog<Map<String, String?>>(
                                          context: context,
                                          builder: (context) => BoardFormDialog(
                                            initialTitle: board.title,
                                            initialDescription:
                                                board.description,
                                          ),
                                        );
                                    if (result != null) {
                                      final now = DateTime.now();
                                      final updatedSlug = _slugify(
                                        result['title'] ?? board.title,
                                      );
                                      final uniqueUpdatedSlug =
                                          updatedSlug.isEmpty
                                          ? board.slug
                                          : _uniqueLocalBoardSlug(
                                              updatedSlug,
                                              board.id,
                                            );
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
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text(l10n.deleteBoard),
                                        content: Text(
                                          l10n.deleteBoardConfirm(board.title),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text(l10n.cancel),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
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
                                      await _hostedBoardRepo
                                          .removeForLocalBoard(board.id);
                                      await _loadData();
                                      setStateDialog(() {});
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
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
          ? HomeBottomBar(
              selectedBoard: _selectedBoard,
              onSelectBoard: _selectBoardSwipe,
              onCompose: () => _selectedBoard == HomeBoard.forum
                  ? _createThread()
                  : _openCompose(context),
              onNotifications: _openNotifications,
              onProfile: _openSettings,
              unreadCount: _notificationUnreadCount,
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
                return mainPanel;
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
