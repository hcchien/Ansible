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
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/board_form_dialog.dart';
import '../widgets/thread_form_dialog.dart';
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
import '../services/contact_source_sync_service.dart';
import '../services/messenger_contact_resolver.dart';
import '../services/messenger_device_service.dart';
import '../services/messenger_relay_client.dart';
import '../services/messenger_sync_service.dart';
import '../services/network_status_service.dart';
import '../services/ops_dispatch_service.dart';
import '../services/content_publication_service.dart';
import '../services/forum_host_client.dart';
import '../services/nostr_relay_settings_store.dart';
import '../services/nostr_secure_key_store.dart';
import '../services/relay_discovery_client.dart';
import '../services/reading_preferences_controller.dart';
import '../services/relay_ops_client.dart';
import '../widgets/ai_provider_setup_sheet.dart';
import '../widgets/feed_filter_tabs.dart';
import '../widgets/ops_queue_status_badge.dart';
import 'murmur_screen.dart';
import 'note_editor_screen.dart';
import 'note_workspace_screen.dart';
import 'posts_view_screen.dart';
import 'contact_picker_screen.dart' show ContactInputResolver;
import 'inbox_screen.dart' show ContactAvailabilityResolver;
import 'search_screen.dart';
import 'settings_home_screen.dart';
import 'sync_settings_screen.dart';
import 'user_profile_screen.dart';
import 'wallet_screen.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';

// Persisted screen-style buckets. The current home surface uses feed/forum.
enum _ElixTab { feed, circle, inbox, you }

/// The two primary swipe boards.
enum _Board { personal, forum }

enum _PersonalFilter { all, murmur, note }

// Within the "圈內" room, a sub-selection between murmur and notes.
enum _CircleTab { murmur, notes }

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.db,
    required this.did,
    this.onClearIdentity,
    this.syncRunner,
    this.pullRefreshRunner,
    this.relayDiscoveryLoader,
    this.networkStatusMonitor,
    this.localeController,
    this.readingPreferencesController,
  });

  final AppDatabase db;
  final String did;
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
  _PersonalFilter _personalFilter = _PersonalFilter.all;
  _ElixTab _selectedTab = _ElixTab.feed;
  _Board _selectedBoard = _Board.personal;
  ElixBoardMotion _boardMotion = ElixBoardMotion.book;
  bool _showCoachmark = false;
  _CircleTab _selectedCircleTab = _CircleTab.murmur;
  late final PageController _pageController;
  Map<_ElixTab, ElixScreenStyle> _screenStyles = {
    for (final tab in _ElixTab.values)
      tab: tab == _ElixTab.feed ? ElixScreenStyle.ink : ElixScreenStyle.paper,
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
    _messengerSyncService = MessengerSyncService(
      repository: _messengerRepo,
      contactRepository: _contactRepo,
      deviceService: _messengerDeviceService,
      relayClient: _messengerRelayClient,
      crypto: _messengerDeviceService.crypto,
      didSigner: DidSignerImpl(),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadScreenStyles());
      unawaited(_loadBoardMotion());
      unawaited(_loadData());
      unawaited(_runForegroundPullIfConfigured());
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
    final followingEntries = _feedFilter == FeedFilter.following
        ? (await _followFeedSource().fetch(
            followerDid: widget.did,
            limit: 100,
          )).items
        : null;
    final threads = followingEntries == null
        ? await _threadRepo.list(boardId: _selectedBoardId)
        : <Thread>[];
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
    final postCards = followingEntries == null
        ? threads.map((t) {
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
            );
          }).toList()
        : await _buildFollowingPostCards(followingEntries, boardMap);

    // Annotate each card with its author's reputation tier (verified badge).
    final authorTiers = await _didReputationRepo.tiersFor(
      postCards.map((card) => card.author).toSet(),
    );
    final tieredCards = postCards
        .map(
          (card) =>
              card.copyWith(authorTier: authorTiers[card.author] ?? 'basic'),
        )
        .toList();

    setState(() {
      _boards = boards;
      _posts = tieredCards;
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

  void _selectFeedFilter(FeedFilter filter) {
    setState(() {
      _feedFilter = filter;
      if (filter == FeedFilter.following || filter == FeedFilter.all) {
        _selectedBoardId = null;
      }
    });
    _loadData();
  }

  void _selectPersonalFilter(_PersonalFilter filter) {
    setState(() => _personalFilter = filter);
  }

  static String _screenStyleKey(_ElixTab tab) =>
      'elix-screen-style.${tab.name}';
  static const _boardMotionKey = 'elix-board-motion';

  Future<void> _loadScreenStyles() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _screenStyles = {
        for (final tab in _ElixTab.values)
          tab: prefs.containsKey(_screenStyleKey(tab))
              ? ElixScreenStyleUi.fromStorage(
                  prefs.getString(_screenStyleKey(tab)),
                )
              : tab == _ElixTab.feed
              ? ElixScreenStyle.ink
              : ElixScreenStyle.paper,
      };
    });
  }

  Future<void> _setScreenStyle(
    _ElixTab tab,
    ElixScreenStyle screenStyle,
  ) async {
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
    final board = _Board.values[page.clamp(0, _Board.values.length - 1)];
    final tab = board == _Board.personal ? _ElixTab.feed : _ElixTab.circle;
    if (_selectedBoard == board && _selectedTab == tab) return;
    setState(() {
      _selectedBoard = board;
      _selectedTab = tab;
    });
  }

  void _selectTab(_ElixTab tab) {
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

  void _selectBoardSwipe(_Board board) {
    if (_selectedBoard != board) {
      setState(() {
        _selectedBoard = board;
        _selectedTab = board == _Board.personal
            ? _ElixTab.feed
            : _ElixTab.circle;
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
    _CircleTab initialTab, {
    bool openNoteEditorOnStart = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CircleFullScreen(
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
      builder: (_) => _ScreenStyleSheet(
        personalStyle: _screenStyles[_ElixTab.feed] ?? ElixScreenStyle.ink,
        forumStyle: _screenStyles[_ElixTab.circle] ?? ElixScreenStyle.paper,
        motion: _boardMotion,
        onPersonalStyleSelected: (style) =>
            unawaited(_setScreenStyle(_ElixTab.feed, style)),
        onForumStyleSelected: (style) =>
            unawaited(_setScreenStyle(_ElixTab.circle, style)),
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
            _ComposeActionItem(
              icon: Icons.mic_outlined,
              title: context.uiCopy(zh: '碎念', en: 'Murmur'),
              subtitle: context.uiCopy(
                zh: 'MURMUR · 文字或語音',
                en: 'MURMUR · text or voice',
              ),
              onTap: () {
                Navigator.pop(context);
                _openCircleScreen(context, _CircleTab.murmur);
              },
            ),
            const Divider(height: 0.5, color: AnsibleDesign.ruleSoft),
            _ComposeActionItem(
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
                  _CircleTab.notes,
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

  void _selectCircleTab(_CircleTab tab) {
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
    if (AppEnvironment.useAppViewFeed && AppEnvironment.appViewBaseUrl.isNotEmpty) {
      return AppViewTimelineSource(
        followRepository: _followRepo,
        fetcher: AppViewTimelineClient(
          baseUrl: AppEnvironment.appViewBaseUrl,
        ).fetch,
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
    );
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
    final intentId = _uuid.v4();
    final createdAt = now.toUtc();
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final canonicalPayload = CreateHostedBoardIntent.canonicalPayload(
      intentId: intentId,
      authorDid: widget.did,
      targetForumHost: forumHost.url,
      title: title,
      description: result['description'],
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
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
  }

  Future<void> _createThread() async {
    final dialogResult = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) =>
          ThreadFormDialog(boards: _boards, initialBoardId: _selectedBoardId),
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
      didReputationRepo: _didReputationRepo,
      followerDid: widget.did,
      opsQueueRepo: _opsQueueRepo,
      opsDispatchService: _opsDispatchService,
      signingBridge: const SchnorrSigningBridge(),
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
    return Scaffold(
      body: SafeArea(
        child: Container(
          color: currentScreenStyle.background,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final mainPanel = _MainPanel(
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
                atProtoClient: _atProtoClient,
                onClearIdentity: widget.onClearIdentity,
                loading: _loading,
                posts: _posts,
                onRefresh: _loadData,
                onCreateThread: _createThread,
                onCreateBoard: _createBoard,
                onManageBoards: _openManageBoards,
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
                selectedTab: _selectedBoard == _Board.personal
                    ? _ElixTab.feed
                    : _ElixTab.circle,
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
                    unawaited(_setScreenStyle(_ElixTab.feed, style)),
                onForumScreenStyleChanged: (style) =>
                    unawaited(_setScreenStyle(_ElixTab.circle, style)),
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
                    child: _Sidebar(
                      boards: _boards,
                      selectedBoardId: _selectedBoardId,
                      onSelectBoard: _selectBoard,
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
            child: _Sidebar(
              boards: _boards,
              selectedBoardId: _selectedBoardId,
              onSelectBoard: (boardId) {
                Navigator.of(sheetContext).pop();
                _selectBoard(boardId);
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.boards,
    required this.selectedBoardId,
    required this.onSelectBoard,
    required this.onManageBoards,
  });

  final List<Board> boards;
  final String? selectedBoardId;
  final ValueChanged<String?> onSelectBoard;
  final VoidCallback onManageBoards;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border(
          right: BorderSide(color: AnsibleDesign.rule.withValues(alpha: 0.8)),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.circleSection,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add),
                color: AnsibleDesign.accent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: boards.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _BoardTile(
                    item: BoardNavItem(
                      title: l10n.allActivity,
                      badge: l10n.boardCount(boards.length),
                      accent: AnsibleDesign.accent,
                    ),
                    selected: selectedBoardId == null,
                    onTap: () => onSelectBoard(null),
                  );
                }
                final board = boards[index - 1];
                return _BoardTile(
                  item: BoardNavItem(
                    title: board.title,
                    badge: null,
                    subtitle: board.slug,
                    accent: AnsibleDesign.accent,
                  ),
                  selected: selectedBoardId == board.id,
                  onTap: () => onSelectBoard(board.id),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onManageBoards,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: Text(l10n.manageSubscriptions),
            style: OutlinedButton.styleFrom(
              foregroundColor: AnsibleDesign.ink,
              side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardTile extends StatefulWidget {
  const _BoardTile({required this.item, this.selected = false, this.onTap});

  final BoardNavItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_BoardTile> createState() => _BoardTileState();
}

class _BoardTileState extends State<_BoardTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final item = widget.item;
    final baseBg = selected ? AnsibleDesign.paperDeep : AnsibleDesign.paperElev;
    final hoverBg = AnsibleDesign.paperDeep;
    final borderColor = selected
        ? item.accent.withValues(alpha: 0.35)
        : (_hover ? AnsibleDesign.rule : AnsibleDesign.ruleSoft);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..translateByDouble(0.0, _hover ? -2.0 : 0.0, 0.0, 1.0),
        decoration: BoxDecoration(
          color: _hover ? hoverBg : baseBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: item.accent.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: item.accent.withValues(alpha: 0.15),
            foregroundColor: item.accent,
            child: const Text(
              '#',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _hover ? item.accent : AnsibleDesign.ink,
            ),
          ),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: const TextStyle(
                    color: AnsibleDesign.inkMuted,
                    fontSize: 12,
                  ),
                )
              : null,
          trailing: item.badge != null
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnsibleDesign.paperDeep,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.badge!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                )
              : null,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

class BoardNavItem {
  BoardNavItem({
    required this.title,
    this.badge,
    this.subtitle,
    this.accent = AnsibleDesign.accent,
  });

  final String title;
  final String? badge;
  final String? subtitle;
  final Color accent;
}

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    this.onClearIdentity,
    required this.db,
    required this.did,
    this.localeController,
    this.readingPreferencesController,
    required this.opsQueueRepo,
    required this.opsDispatchService,
    required this.messengerSyncService,
    required this.contactAvailabilityResolver,
    required this.contactInputResolver,
    required this.hasActiveRelay,
    required this.showFirstRunDiscovery,
    required this.firstRunDiscovery,
    required this.firstRunDiscoveryLoading,
    required this.onOpenDiscoveredForumHost,
    required this.onFlushPendingOps,
    required this.onSync,
    required this.syncing,
    required this.atProtoClient,
    required this.loading,
    required this.posts,
    required this.onRefresh,
    required this.onCreateThread,
    required this.onCreateBoard,
    required this.onManageBoards,
    this.onOpenBoards,
    required this.feedFilter,
    required this.onFeedFilterChanged,
    required this.personalFilter,
    required this.onPersonalFilterChanged,
    required this.hasSelectedBoard,
    required this.selectedBoardId,
    required this.boards,
    required this.networkStatusService,
    required this.pageController,
    required this.selectedTab,
    required this.onTabChanged,
    required this.onPageChanged,
    required this.selectedBoard,
    required this.onBoardChanged,
    required this.showCoachmark,
    required this.onDismissCoachmark,
    required this.onOpenCircle,
    required this.onComposeTap,
    required this.onScreenStyleTap,
    required this.onPersonalScreenStyleChanged,
    required this.onForumScreenStyleChanged,
    required this.onBoardMotionChanged,
    required this.screenStyles,
    required this.boardMotion,
    required this.selectedCircleTab,
    required this.onCircleTabChanged,
    required this.contentItemRepository,
    required this.contentItems,
    required this.murmurReferenceCounts,
    required this.onContentItemsChanged,
    required this.onPublishContentItem,
    required this.onStartAiAction,
    required this.onSummonAiForNote,
  });

  final VoidCallback? onClearIdentity;
  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;
  final OpsQueueRepository opsQueueRepo;
  final OpsDispatchService opsDispatchService;
  final MessengerSyncService messengerSyncService;
  final ContactAvailabilityResolver contactAvailabilityResolver;
  final ContactInputResolver contactInputResolver;
  final bool hasActiveRelay;
  final bool showFirstRunDiscovery;
  final RelayDiscovery? firstRunDiscovery;
  final bool firstRunDiscoveryLoading;
  final ValueChanged<String> onOpenDiscoveredForumHost;
  final Future<void> Function() onFlushPendingOps;
  final Future<void> Function() onSync;
  final bool syncing;
  final AtProtoClient atProtoClient;
  final bool loading;
  final List<PostCardData> posts;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateThread;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onManageBoards;
  final VoidCallback? onOpenBoards;
  final FeedFilter feedFilter;
  final ValueChanged<FeedFilter> onFeedFilterChanged;
  final _PersonalFilter personalFilter;
  final ValueChanged<_PersonalFilter> onPersonalFilterChanged;
  final bool hasSelectedBoard;
  final String? selectedBoardId;
  final List<Board> boards;
  final NetworkStatusMonitor networkStatusService;
  final PageController pageController;
  final _ElixTab selectedTab;
  final ValueChanged<_ElixTab> onTabChanged;
  final ValueChanged<int> onPageChanged;
  final _Board selectedBoard;
  final ValueChanged<_Board> onBoardChanged;
  final bool showCoachmark;
  final VoidCallback onDismissCoachmark;
  final void Function(BuildContext, _CircleTab) onOpenCircle;
  final VoidCallback onComposeTap;
  final VoidCallback onScreenStyleTap;
  final ValueChanged<ElixScreenStyle> onPersonalScreenStyleChanged;
  final ValueChanged<ElixScreenStyle> onForumScreenStyleChanged;
  final ValueChanged<ElixBoardMotion> onBoardMotionChanged;
  final Map<_ElixTab, ElixScreenStyle> screenStyles;
  final ElixBoardMotion boardMotion;
  final _CircleTab selectedCircleTab;
  final ValueChanged<_CircleTab> onCircleTabChanged;
  final ContentItemRepository contentItemRepository;
  final List<ContentItem> contentItems;
  final Map<String, int> murmurReferenceCounts;
  final Future<void> Function() onContentItemsChanged;
  final Future<void> Function(ContentItem, DistributionPreference)
  onPublishContentItem;
  final Future<void> Function() onStartAiAction;
  final Future<void> Function({
    String? noteId,
    String? noteTitle,
    String? noteBody,
  })
  onSummonAiForNote;

  Widget _buildFirstRunDiscoverySection(BuildContext context) {
    if (!showFirstRunDiscovery) return const SizedBox.shrink();
    final discovery = firstRunDiscovery;
    if (discovery == null && !firstRunDiscoveryLoading) {
      return const SizedBox.shrink();
    }
    final announcements =
        discovery?.announcements ?? const <RelayAnnouncement>[];
    final starterBoards =
        discovery?.featuredBoards ?? const <DiscoveredBoard>[];
    final hostComplianceByUrl = {
      for (final host
          in discovery?.featuredForumHosts ?? const <DiscoveredForumHost>[])
        host.forumHostUrl: host.constitutionCompliance,
    };
    if (discovery != null && announcements.isEmpty && starterBoards.isEmpty) {
      return const SizedBox.shrink();
    }

    final styleData = ElixScreenStyleScope.dataOf(context);
    final text = SubpageL10n.of(context);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: AnsibleMonoLabel(text.t('forumHosts')),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: styleData.surface.withValues(alpha: 0.55),
          border: Border(
            top: BorderSide(color: styleData.rule, width: 0.5),
            bottom: BorderSide(color: styleData.rule, width: 0.5),
          ),
        ),
        child: Column(
          children: [
            if (firstRunDiscoveryLoading && discovery == null)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            for (final announcement in announcements)
              _FirstRunDiscoveryRow(
                icon: Icons.campaign_outlined,
                title: announcement.title,
                subtitle: announcement.body,
                ruleColor: styleData.rule,
              ),
            for (final board in starterBoards)
              _FirstRunDiscoveryRow(
                icon: Icons.forum_outlined,
                title: board.title,
                subtitle: board.description ?? board.forumHostUrl,
                ruleColor: styleData.rule,
                compliance: _starterBoardCompliance(board, hostComplianceByUrl),
                action: OutlinedButton.icon(
                  onPressed: () =>
                      onOpenDiscoveredForumHost(board.forumHostUrl),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    text.t('addForumHost'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  String _starterBoardCompliance(
    DiscoveredBoard board,
    Map<String, String> hostComplianceByUrl,
  ) {
    final boardCompliance = board.constitutionCompliance.trim();
    if (boardCompliance.isNotEmpty) return boardCompliance;
    final hostCompliance = hostComplianceByUrl[board.forumHostUrl]?.trim();
    if (hostCompliance != null && hostCompliance.isNotEmpty) {
      return hostCompliance;
    }
    return 'unknown';
  }

  // ── Personal board (個人版) — A·01 spec ──────────────────────────────────
  Widget _buildPersonalBoard(BuildContext context, bool compact) {
    final styleData = ElixScreenStyleScope.dataOf(context);
    final fgColor = styleData.foreground;
    final mutedColor = styleData.muted;
    final faintColor = styleData.faint;
    final bgSoftColor = styleData.surface;
    final borderSoft = styleData.rule;
    final emberColor = AnsibleDesign.ember;

    // A·01 time-ago formatting — matches design's "昨 14:36 / 前天 / MM.DD" style
    String timeAgo(DateTime dt) {
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) {
        return context.uiCopy(zh: '剛剛', en: 'just now');
      }
      if (diff.inDays < 1) {
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return diff.inHours < 1
            ? '${diff.inMinutes}m'
            : context.uiCopy(zh: '今 $hh:$mm', en: 'today $hh:$mm');
      }
      if (diff.inDays == 1) {
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return context.uiCopy(zh: '昨 $hh:$mm', en: 'yesterday $hh:$mm');
      }
      if (diff.inDays == 2) return context.uiCopy(zh: '前天', en: '2d ago');
      if (diff.inDays < 7) {
        return context.uiCopy(
          zh: '${diff.inDays} 天前',
          en: '${diff.inDays}d ago',
        );
      }
      return '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    }

    final filteredItems = switch (personalFilter) {
      _PersonalFilter.all => contentItems,
      _PersonalFilter.murmur =>
        contentItems.where((item) => item.mode == ContentMode.murmur).toList(),
      _PersonalFilter.note =>
        contentItems.where((item) => item.mode == ContentMode.note).toList(),
    };
    final allSorted = [...filteredItems]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Split into this-week and earlier
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDay = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );
    final thisWeek = allSorted
        .where((i) => i.createdAt.isAfter(weekStartDay))
        .toList();
    final earlier = allSorted
        .where((i) => !i.createdAt.isAfter(weekStartDay))
        .toList();

    // ── diary entry card (A·01 style) ──
    // Shows: pip + type-label + time on top row, then title (for notes), then italic preview
    Widget diaryCard(ContentItem item) {
      final isNote = item.mode == ContentMode.note;
      final pipColor = isNote ? fgColor : emberColor;
      final typeLabel = isNote ? 'NOTE' : 'MURMUR';

      return GestureDetector(
        onTap: () {
          onOpenCircle(context, isNote ? _CircleTab.notes : _CircleTab.murmur);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: styleData.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderSoft, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Meta row: pip · TYPE · time
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pipColor,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 8.5,
                      letterSpacing: 1.4,
                      color: faintColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeAgo(item.createdAt),
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 8.5,
                      letterSpacing: 0.5,
                      color: faintColor,
                    ),
                  ),
                ],
              ),
              // Title — only for notes
              if (isNote && item.title != null && item.title!.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  item.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: fgColor,
                    height: 1.3,
                  ),
                ),
              ],
              // Preview body
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13,
                    color: mutedColor,
                    fontStyle: isNote ? FontStyle.normal : FontStyle.italic,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ── section kicker ──
    Widget sectionKicker(String zh, String en) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            Text(
              zh,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9.5,
                letterSpacing: 1.4,
                color: faintColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· $en',
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9.5,
                letterSpacing: 1.4,
                color: faintColor,
              ),
            ),
          ],
        ),
      );
    }

    Widget aiBridge() {
      return InkWell(
        key: const Key('home_ai_bridge'),
        onTap: onStartAiAction,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: bgSoftColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderSoft, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 38,
                decoration: BoxDecoration(
                  color: styleData.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 11),
              AnsibleMark(size: 18, color: fgColor),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.uiCopy(zh: 'AI · 橫向橋', en: 'AI · BRIDGE'),
                      style: TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9.5,
                        letterSpacing: 1.3,
                        color: styleData.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.uiCopy(
                        zh: '從本機 murmur 找材料，替筆記接出下一段。',
                        en: 'Find local murmurs and extend the next paragraph.',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        height: 1.35,
                        color: mutedColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: faintColor),
            ],
          ),
        ),
      );
    }

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            aiBridge(),
            const SizedBox(height: 14),
            _buildFirstRunDiscoverySection(context),

            // ── This week section ────────────────────────────────────────
            if (thisWeek.isNotEmpty) ...[
              sectionKicker(
                context.uiCopy(zh: '本週', en: 'This week'),
                'THIS WEEK',
              ),
              ...thisWeek.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: diaryCard(item),
                ),
              ),
            ],

            // ── Earlier section ──────────────────────────────────────────
            if (earlier.isNotEmpty) ...[
              sectionKicker(
                context.uiCopy(zh: '上週', en: 'Earlier'),
                context.uiCopy(zh: '更早', en: 'OLDER'),
              ),
              ...earlier.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: diaryCard(item),
                ),
              ),
            ],

            // ── Empty state ──────────────────────────────────────────────
            if (allSorted.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    context.uiCopy(zh: '還沒有任何記錄', en: 'No entries yet'),
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 15,
                      color: faintColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ── Floating AI dot (A·01 bottom-right, 56×56) ──
        Positioned(
          right: 0,
          bottom: 92,
          child: FloatingActionButton.small(
            key: const Key('home_compose_button'),
            heroTag: 'home_compose_button',
            onPressed: onComposeTap,
            backgroundColor: styleData.accent,
            foregroundColor: styleData.background,
            elevation: 0,
            tooltip: context.uiCopy(
              zh: '新增 Note 或 Murmur',
              en: 'New Note or Murmur',
            ),
            child: const Icon(Icons.add),
          ),
        ),

        Positioned(
          right: 0,
          bottom: 24,
          child: ElixAIDot(
            key: const Key('home_ai_button'),
            onTap: onStartAiAction,
          ),
        ),
      ],
    );
  }

  // ── Forum board (討論區) ────────────────────────────────────────────────
  // ignore: unused_element -- retained for the forum surface while the swipe shell exposes primary tabs first.
  Widget _buildForum(BuildContext context, bool compact) {
    final l10n = context.l10n;
    final styleData = ElixScreenStyleScope.dataOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          FeedFilterTabs(selected: feedFilter, onChanged: onFeedFilterChanged),
          const SizedBox(height: 12),
          // Board actions row
          LayoutBuilder(
            builder: (context, actionConstraints) {
              final actionWidth = compact
                  ? (actionConstraints.maxWidth - 10) / 2
                  : null;
              Widget action(Widget child) =>
                  compact ? SizedBox(width: actionWidth, child: child) : child;

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  action(
                    OutlinedButton.icon(
                      onPressed: onCreateBoard,
                      icon: const Icon(Icons.add),
                      label: _ActionLabel(l10n.addBoardTooltip),
                    ),
                  ),
                  action(
                    FilledButton.icon(
                      onPressed: hasSelectedBoard ? onCreateThread : null,
                      icon: const Icon(Icons.forum_outlined),
                      label: _ActionLabel(
                        compact ? l10n.newDiscussion : l10n.createNewDiscussion,
                      ),
                    ),
                  ),
                  action(
                    OutlinedButton.icon(
                      onPressed: onManageBoards,
                      icon: const Icon(Icons.settings_outlined),
                      label: _ActionLabel(
                        compact ? l10n.boardsShort : l10n.manageBoardsShort,
                      ),
                    ),
                  ),
                  action(
                    OutlinedButton.icon(
                      onPressed: () {
                        if (hasSelectedBoard && selectedBoardId != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NoteEditorScreen(
                                authorDid: did,
                                boardId: selectedBoardId!,
                                threadId: '',
                                threadTitle:
                                    boards
                                        .where((b) => b.id == selectedBoardId)
                                        .map((b) => b.title)
                                        .firstOrNull ??
                                    l10n.newDiscussion,
                                atProtoClient: atProtoClient,
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: _ActionLabel(l10n.newPost),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : posts.isEmpty
              ? Center(
                  child: Text(
                    l10n.noPostsYet,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => PostCard(
                    db: db,
                    data: posts[index],
                    authorDid: did,
                    opsDispatchService: opsDispatchService,
                    onFlushPendingOps: onFlushPendingOps,
                    onOpenAuthor: (authorDid) {
                      if (authorDid.isEmpty || authorDid == did) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            db: db,
                            followerDid: did,
                            did: authorDid,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        // Bottom action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: styleData.rule, width: 0.5)),
            color: styleData.background,
          ),
          child: Row(
            children: [
              Text(
                context.uiCopy(zh: '在討論區', en: 'In forum'),
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 9.5,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: hasSelectedBoard ? onCreateThread : onCreateBoard,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.newPost),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBoardSwiper(BuildContext context, bool compact) {
    final contentPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 28, vertical: 12);

    Widget wrapPage(_ElixTab tab, Widget child) {
      final style = screenStyles[tab] ?? ElixScreenStyle.paper;
      final data = style.dataFor(Theme.of(context).brightness);
      return ElixScreenStyleScope(
        style: style,
        child: AnimatedContainer(
          key: Key('screen_style_scope_${tab.name}'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(color: data.background),
          child: child,
        ),
      );
    }

    return Stack(
      key: const Key('board_swipe_3d_stage'),
      children: [
        PageView(
          key: const Key('board_swipe_page_view'),
          controller: pageController,
          onPageChanged: onPageChanged,
          physics: const PageScrollPhysics(),
          allowImplicitScrolling: true,
          children: [
            _BoardFlipPage(
              key: const Key('board_swipe_page_transform_feed'),
              pageController: pageController,
              pageIndex: _Board.personal.index,
              selectedBoard: selectedBoard,
              motion: boardMotion,
              child: wrapPage(
                _ElixTab.feed,
                Padding(
                  padding: contentPadding,
                  child: _buildPersonalBoard(context, compact),
                ),
              ),
            ),
            _BoardFlipPage(
              key: const Key('board_swipe_page_transform_circle'),
              pageController: pageController,
              pageIndex: _Board.forum.index,
              selectedBoard: selectedBoard,
              motion: boardMotion,
              child: wrapPage(
                _ElixTab.circle,
                Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 16 : 28,
                    right: compact ? 16 : 28,
                    top: 12,
                  ),
                  child: _buildForum(context, compact),
                ),
              ),
            ),
          ],
        ),
        _BoardSwipeProgressPill(
          pageController: pageController,
          compact: compact,
          motion: boardMotion,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              _TopBar(
                onClearIdentity: onClearIdentity,
                db: db,
                did: did,
                localeController: localeController,
                readingPreferencesController: readingPreferencesController,
                opsQueueRepo: opsQueueRepo,
                onSync: onSync,
                syncing: syncing,
                networkStatusService: networkStatusService,
                contentItems: contentItems,
                messengerSyncService: messengerSyncService,
                contactAvailabilityResolver: contactAvailabilityResolver,
                contactInputResolver: contactInputResolver,
                hasActiveRelay: hasActiveRelay,
                screenStyle: screenStyles[selectedTab] ?? ElixScreenStyle.paper,
                onScreenStyleTap: onScreenStyleTap,
                screenStyleLabel:
                    (screenStyles[selectedTab] ?? ElixScreenStyle.paper).label,
                personalScreenStyle:
                    screenStyles[_ElixTab.feed] ?? ElixScreenStyle.ink,
                forumScreenStyle:
                    screenStyles[_ElixTab.circle] ?? ElixScreenStyle.paper,
                boardMotion: boardMotion,
                onPersonalScreenStyleChanged: onPersonalScreenStyleChanged,
                onForumScreenStyleChanged: onForumScreenStyleChanged,
                onBoardMotionChanged: onBoardMotionChanged,
              ),
            _BoardSwipeHeader(
              pageController: pageController,
              selectedBoard: selectedBoard,
              onTapBoard: onBoardChanged,
              personalStyle: screenStyles[_ElixTab.feed] ?? ElixScreenStyle.ink,
              forumStyle:
                  screenStyles[_ElixTab.circle] ?? ElixScreenStyle.paper,
              personalFilter: personalFilter,
              onPersonalFilterChanged: onPersonalFilterChanged,
              feedFilter: feedFilter,
              onFeedFilterChanged: onFeedFilterChanged,
              forumPostCount: posts.length,
              onOpenPreferences: null,
              onOpenSettings: compact
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => SettingsHomeScreen(
                            db: db,
                            did: did,
                            localeController: localeController,
                            readingPreferencesController:
                                readingPreferencesController,
                            onClearIdentity: onClearIdentity,
                            personalScreenStyle:
                                screenStyles[_ElixTab.feed] ??
                                ElixScreenStyle.ink,
                            forumScreenStyle:
                                screenStyles[_ElixTab.circle] ??
                                ElixScreenStyle.paper,
                            boardMotion: boardMotion,
                            onPersonalScreenStyleChanged:
                                onPersonalScreenStyleChanged,
                            onForumScreenStyleChanged:
                                onForumScreenStyleChanged,
                            onBoardMotionChanged: onBoardMotionChanged,
                          ),
                        ),
                      );
                    }
                  : null,
            ),
            Expanded(
              child: Stack(
                children: [
                  _buildBoardSwiper(context, compact),
                  if (showCoachmark)
                    _SwipeCoachmark(onDismiss: onDismissCoachmark),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

class _FirstRunDiscoveryRow extends StatelessWidget {
  const _FirstRunDiscoveryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ruleColor,
    this.compliance,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color ruleColor;
  final String? compliance;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final styleData = ElixScreenStyleScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ruleColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: styleData.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: styleData.foreground,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 12.5,
                      height: 1.35,
                      color: styleData.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (compliance != null) ...[
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: styleData.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ruleColor, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  compliance!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 0.6,
                    color: styleData.faint,
                  ),
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: action!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ComposeActionItem extends StatelessWidget {
  const _ComposeActionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AnsibleDesign.paperElev,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: AnsibleDesign.ink),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1.0,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right,
              color: AnsibleDesign.inkFaint,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenStyleSheet extends StatelessWidget {
  const _ScreenStyleSheet({
    required this.personalStyle,
    required this.forumStyle,
    required this.motion,
    required this.onPersonalStyleSelected,
    required this.onForumStyleSelected,
    required this.onMotionSelected,
  });

  final ElixScreenStyle personalStyle;
  final ElixScreenStyle forumStyle;
  final ElixBoardMotion motion;
  final ValueChanged<ElixScreenStyle> onPersonalStyleSelected;
  final ValueChanged<ElixScreenStyle> onForumStyleSelected;
  final ValueChanged<ElixBoardMotion> onMotionSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AnsibleDesign.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.uiCopy(zh: '介面與語言', en: 'Interface & Language'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 14),
              AnsibleMonoLabel(context.uiCopy(zh: '每版的光', en: 'BOARD THEME')),
              const SizedBox(height: 8),
              Text(
                context.uiCopy(
                  zh: '每個版可以有自己的光。Swipe 換版時，顏色也會跟著換。',
                  en: 'Each board can have its own theme. Colors follow when you swipe between boards.',
                ),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 13,
                  height: 1.65,
                  color: AnsibleDesign.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              _BoardAtmosphereCard(
                boardLabel: context.uiCopy(zh: '個人版', en: 'Personal'),
                boardMeta: context.uiCopy(zh: '寫給自己', en: 'For yourself'),
                selected: personalStyle,
                keyPrefix: 'feed',
                onSelected: onPersonalStyleSelected,
              ),
              const SizedBox(height: 10),
              _BoardAtmosphereCard(
                boardLabel: context.uiCopy(zh: '討論區', en: 'Forum'),
                boardMeta: context.uiCopy(zh: '白天的廣場', en: 'Daylight square'),
                selected: forumStyle,
                keyPrefix: 'circle',
                onSelected: onForumStyleSelected,
              ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AnsibleDesign.paperElev,
                  border: Border(
                    left: BorderSide(color: AnsibleDesign.ochre, width: 2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Text(
                    context.uiCopy(
                      zh: '不開放選別的顏色。寫過的東西仍是同一個品牌，只是換了一面光。',
                      en: 'Custom colors are not available. Your writing stays in the same brand, with a different light.',
                    ),
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 12,
                      height: 1.65,
                      color: AnsibleDesign.inkMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AnsibleMonoLabel(context.uiCopy(zh: '換版的動態', en: 'BOARD MOTION')),
              const SizedBox(height: 8),
              Text(
                context.uiCopy(
                  zh: '如果系統開了「減少動態」，Elix 會自動降回平移。',
                  en: 'When Reduce Motion is enabled, Elix automatically falls back to slide.',
                ),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 13,
                  height: 1.65,
                  color: AnsibleDesign.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              _MotionOption(
                key: const Key('board_motion_slide'),
                title: context.uiCopy(zh: 'Slide · 平移', en: 'Slide'),
                subtitle: context.uiCopy(
                  zh: '兩張紙左右平移，沒有立體感。',
                  en: 'Two pages slide side to side with no 3D effect.',
                ),
                selected: motion == ElixBoardMotion.slide,
                onTap: () => onMotionSelected(ElixBoardMotion.slide),
              ),
              _MotionOption(
                key: const Key('board_motion_book'),
                title: context.uiCopy(zh: 'Book · 翻書', en: 'Book'),
                badge: context.uiCopy(zh: '預設', en: 'Default'),
                subtitle: context.uiCopy(
                  zh: '兩個版像書的左右頁，輕微 perspective。',
                  en: 'Boards turn like left and right pages with light perspective.',
                ),
                selected: motion == ElixBoardMotion.book,
                onTap: () => onMotionSelected(ElixBoardMotion.book),
              ),
              _MotionOption(
                key: const Key('board_motion_cube'),
                title: context.uiCopy(zh: 'Cube · 翻立方', en: 'Cube'),
                subtitle: context.uiCopy(
                  zh: '較完整的 rotateY，切換感更強。',
                  en: 'Fuller rotateY motion with a stronger switch feel.',
                ),
                selected: motion == ElixBoardMotion.cube,
                onTap: () => onMotionSelected(ElixBoardMotion.cube),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardAtmosphereCard extends StatelessWidget {
  const _BoardAtmosphereCard({
    required this.boardLabel,
    required this.boardMeta,
    required this.selected,
    required this.keyPrefix,
    required this.onSelected,
  });

  final String boardLabel;
  final String boardMeta;
  final ElixScreenStyle selected;
  final String keyPrefix;
  final ValueChanged<ElixScreenStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
      ),
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            Row(
              children: [
                if (keyPrefix == 'feed') ...[
                  const AnsibleMark(size: 13),
                  const SizedBox(width: 8),
                ] else ...[
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AnsibleDesign.ink, width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  boardLabel,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  boardMeta,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1.1,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final style in ElixScreenStyle.values) ...[
                  Expanded(
                    child: _ScreenStyleSwatch(
                      key: Key(
                        'screen_style_choice_${keyPrefix}_${style.name}',
                      ),
                      style: style,
                      selected: selected == style,
                      onTap: () => onSelected(style),
                    ),
                  ),
                  if (style != ElixScreenStyle.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenStyleSwatch extends StatelessWidget {
  const _ScreenStyleSwatch({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final ElixScreenStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.paperElev : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            _StylePreview(style: style),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.circle_outlined,
                  size: 10,
                  color: selected
                      ? AnsibleDesign.ochre
                      : AnsibleDesign.inkFaint,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    context.uiCopy(zh: style.zhLabel, en: style.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: selected
                          ? AnsibleDesign.ink
                          : AnsibleDesign.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.style});

  final ElixScreenStyle style;

  @override
  Widget build(BuildContext context) {
    final data = style.dataFor(Theme.of(context).brightness);
    final decoration = style == ElixScreenStyle.system
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0.5, 0.5],
              colors: [AnsibleDesign.paper, AnsibleDesign.darkPaper],
            ),
          )
        : BoxDecoration(
            color: data.background,
            borderRadius: BorderRadius.circular(5),
          );
    final lineColor = style == ElixScreenStyle.ink
        ? AnsibleDesign.darkInk
        : AnsibleDesign.ink;
    final mutedLine = style == ElixScreenStyle.ink
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
    final dotColor = style == ElixScreenStyle.ink
        ? AnsibleDesign.darkOchre
        : AnsibleDesign.ochre;

    return Container(
      height: 48,
      decoration: decoration,
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              width: 18,
              height: 1.5,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 8,
            child: Container(
              width: 28,
              height: 1.5,
              decoration: BoxDecoration(
                color: mutedLine,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            right: 7,
            bottom: 7,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotionOption extends StatelessWidget {
  const _MotionOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.paperElev : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.circle_outlined,
              size: 16,
              color: selected ? AnsibleDesign.ochre : AnsibleDesign.inkFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AnsibleDesign.ochre,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontFamily: AnsibleDesign.mono,
                              fontSize: 9.5,
                              letterSpacing: 1.1,
                              color: AnsibleDesign.ochre,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    this.onClearIdentity,
    required this.db,
    required this.did,
    this.localeController,
    this.readingPreferencesController,
    required this.opsQueueRepo,
    required this.onSync,
    required this.syncing,
    required this.networkStatusService,
    required this.contentItems,
    required this.messengerSyncService,
    required this.contactAvailabilityResolver,
    required this.contactInputResolver,
    required this.hasActiveRelay,
    required this.screenStyle,
    required this.onScreenStyleTap,
    required this.screenStyleLabel,
    required this.personalScreenStyle,
    required this.forumScreenStyle,
    required this.boardMotion,
    required this.onPersonalScreenStyleChanged,
    required this.onForumScreenStyleChanged,
    required this.onBoardMotionChanged,
  });

  final VoidCallback? onClearIdentity;
  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;
  final OpsQueueRepository opsQueueRepo;
  final Future<void> Function() onSync;
  final bool syncing;
  final NetworkStatusMonitor networkStatusService;
  final List<ContentItem> contentItems;
  final MessengerSyncService messengerSyncService;
  final ContactAvailabilityResolver contactAvailabilityResolver;
  final ContactInputResolver contactInputResolver;
  final bool hasActiveRelay;
  final ElixScreenStyle screenStyle;
  final VoidCallback onScreenStyleTap;
  final String screenStyleLabel;
  final ElixScreenStyle personalScreenStyle;
  final ElixScreenStyle forumScreenStyle;
  final ElixBoardMotion boardMotion;
  final ValueChanged<ElixScreenStyle> onPersonalScreenStyleChanged;
  final ValueChanged<ElixScreenStyle> onForumScreenStyleChanged;
  final ValueChanged<ElixBoardMotion> onBoardMotionChanged;

  String get _truncatedDid {
    if (did.length <= 24) return did;
    return '${did.substring(0, 18)}...${did.substring(did.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styleData = screenStyle.dataFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: styleData.background,
        border: Border(bottom: BorderSide(color: styleData.rule, width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;

          return Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnsibleMark(size: compact ? 34 : 38),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    const ElixWordmark(fontSize: 24),
                  ],
                ],
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: networkStatusService,
                builder: (context, _) {
                  return _NetworkStatusIndicator(
                    status: networkStatusService.status,
                    connectionType: networkStatusService.connectionType,
                    compact: compact,
                    onTap: () => networkStatusService.checkStatus(),
                  );
                },
              ),
              SizedBox(width: compact ? 2 : 8),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchScreen(contentItems: contentItems),
                    ),
                  );
                },
                icon: const Icon(Icons.search),
                color: styleData.muted,
                tooltip: l10n.search,
              ),
              IconButton(
                key: const Key('screen_style_button'),
                onPressed: onScreenStyleTap,
                icon: const Icon(Icons.palette_outlined),
                color: styleData.muted,
                tooltip: 'Screen style · $screenStyleLabel',
              ),
              IconButton(
                key: const Key('settings_button'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsHomeScreen(
                        db: db,
                        did: did,
                        localeController: localeController,
                        readingPreferencesController:
                            readingPreferencesController,
                        onClearIdentity: onClearIdentity,
                        personalScreenStyle: personalScreenStyle,
                        forumScreenStyle: forumScreenStyle,
                        boardMotion: boardMotion,
                        onPersonalScreenStyleChanged:
                            onPersonalScreenStyleChanged,
                        onForumScreenStyleChanged: onForumScreenStyleChanged,
                        onBoardMotionChanged: onBoardMotionChanged,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person_outline),
                color: styleData.muted,
                tooltip: l10n.settingsNav,
              ),
              if (!compact)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WalletScreen(
                          holderDid: did,
                          repository: DriftWalletRepository(db),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text(l10n.wallet),
                  style: TextButton.styleFrom(
                    foregroundColor: AnsibleDesign.paper,
                    backgroundColor: AnsibleDesign.ink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnsibleDesign.paperElev,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ElixSignedPill(kind: 'PK'),
                      const SizedBox(width: 8),
                      Text(
                        _truncatedDid,
                        style: const TextStyle(
                          color: AnsibleDesign.inkMuted,
                          fontSize: 12,
                          fontFamily: AnsibleDesign.mono,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OpsQueueStatusBadge(repository: opsQueueRepo),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                onPressed: syncing ? null : onSync,
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                color: styleData.muted,
                tooltip: l10n.sync,
              ),
            ],
          );
        },
      ),
    );
  }
}

double _boardPageValue(PageController controller, double fallback) {
  if (!controller.hasClients) return fallback;
  final position = controller.position;
  if (!position.hasContentDimensions) return fallback;
  return controller.page ?? fallback;
}

class _BoardFlipPage extends StatelessWidget {
  const _BoardFlipPage({
    super.key,
    required this.pageController,
    required this.pageIndex,
    required this.selectedBoard,
    required this.motion,
    required this.child,
  });

  final PageController pageController;
  final int pageIndex;
  final _Board selectedBoard;
  final ElixBoardMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      child: child,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final reduceMotion =
            media.disableAnimations || media.accessibleNavigation;
        final currentPage = _boardPageValue(
          pageController,
          selectedBoard.index.toDouble(),
        );
        final delta = (currentPage - pageIndex).clamp(-1.0, 1.0).toDouble();
        final depth = delta.abs();
        final matrix = Matrix4.identity();
        if (reduceMotion || motion == ElixBoardMotion.slide) {
          matrix.translateByDouble(-delta * 10.0, 0.0, 0.0, 1.0);
        } else if (motion == ElixBoardMotion.book) {
          matrix
            ..setEntry(3, 2, 0.0012)
            ..translateByDouble(-delta * 28.0, 0.0, 0.0, 1.0)
            ..rotateY(-delta * 0.56);
        } else {
          matrix
            ..setEntry(3, 2, 0.0018)
            ..translateByDouble(-delta * 44.0, 0.0, 0.0, 1.0)
            ..rotateY(-delta * 1.18);
        }

        final hinge = delta >= 0 ? Alignment.centerLeft : Alignment.centerRight;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final shadeColor = dark
            ? Colors.black.withValues(alpha: 0.34)
            : AnsibleDesign.ink.withValues(alpha: 0.20);
        final spineColor = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;

        return Transform(
          alignment: hinge,
          transform: matrix,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (!reduceMotion &&
                  motion != ElixBoardMotion.slide &&
                  depth > 0.01)
                IgnorePointer(
                  child: Opacity(
                    opacity: depth.clamp(0.0, 0.82).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: delta >= 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          end: delta >= 0
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          colors: [Colors.transparent, shadeColor],
                          stops: const [0.34, 1.0],
                        ),
                        border: Border(
                          right: delta >= 0
                              ? BorderSide(color: spineColor, width: 0.5)
                              : BorderSide.none,
                          left: delta < 0
                              ? BorderSide(color: spineColor, width: 0.5)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardSwipeProgressPill extends StatelessWidget {
  const _BoardSwipeProgressPill({
    required this.pageController,
    required this.compact,
    required this.motion,
  });

  final PageController pageController;
  final bool compact;
  final ElixBoardMotion motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        final page = _boardPageValue(
          pageController,
          0.0,
        ).clamp(0.0, 1.0).toDouble();
        final fractional = page - page.floorToDouble();
        final distanceFromEdge = fractional <= 0.5
            ? fractional
            : 1.0 - fractional;
        if (distanceFromEdge < 0.035) return const SizedBox.shrink();

        final targetLabel = page < 0.5
            ? context.uiCopy(zh: '換到討論區', en: 'Switch to Forum')
            : context.uiCopy(zh: '換到個人版', en: 'Switch to Personal');
        final progress = page < 0.5 ? page : 1.0 - page;
        final percent = (progress.clamp(0.0, 1.0) * 100).round();
        final dark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = dark
            ? AnsibleDesign.darkPaperElev
            : AnsibleDesign.paper;
        final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;

        return Positioned(
          left: 0,
          right: 0,
          bottom: compact ? 18 : 26,
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ochreColor, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        page < 0.5
                            ? Icons.chevron_left_rounded
                            : Icons.chevron_right_rounded,
                        size: 15,
                        color: ochreColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        motion == ElixBoardMotion.book
                            ? '$targetLabel · $percent%'
                            : targetLabel,
                        style: TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: ochreColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Centered swipe header with animated ochre underline.
class _BoardSwipeHeader extends StatelessWidget {
  const _BoardSwipeHeader({
    required this.pageController,
    required this.selectedBoard,
    required this.onTapBoard,
    required this.personalStyle,
    required this.forumStyle,
    required this.personalFilter,
    required this.onPersonalFilterChanged,
    required this.feedFilter,
    required this.onFeedFilterChanged,
    required this.forumPostCount,
    this.onOpenPreferences,
    this.onOpenSettings,
  });

  final PageController pageController;
  final _Board selectedBoard;
  final ValueChanged<_Board> onTapBoard;
  final ElixScreenStyle personalStyle;
  final ElixScreenStyle forumStyle;
  final _PersonalFilter personalFilter;
  final ValueChanged<_PersonalFilter> onPersonalFilterChanged;
  final FeedFilter feedFilter;
  final ValueChanged<FeedFilter> onFeedFilterChanged;
  final int forumPostCount;
  final VoidCallback? onOpenPreferences;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final personalData = personalStyle.dataFor(brightness);
    final forumData = forumStyle.dataFor(brightness);

    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        final page = _boardPageValue(
          pageController,
          selectedBoard.index.toDouble(),
        ).clamp(0.0, 1.0).toDouble();
        final bgColor = Color.lerp(
          personalData.background,
          forumData.background,
          page,
        )!;
        final ruleColor = Color.lerp(personalData.rule, forumData.rule, page)!;
        final fgColor = Color.lerp(
          personalData.foreground,
          forumData.foreground,
          page,
        )!;
        final faintColor = Color.lerp(
          personalData.faint,
          forumData.faint,
          page,
        )!;
        final mutedColor = Color.lerp(
          personalData.muted,
          forumData.muted,
          page,
        )!;
        final surfaceColor = Color.lerp(
          personalData.surface,
          forumData.surface,
          page,
        )!;
        final ochreColor = Color.lerp(
          personalData.accent,
          forumData.accent,
          page,
        )!;

        return Container(
          color: bgColor,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.topCenter,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _boardButton(
                        board: _Board.personal,
                        label: context.uiCopy(zh: '個人版', en: 'Personal'),
                        tooltip: context.uiCopy(
                          zh: '個人版 · 你的 Note 和 Murmur',
                          en: 'Personal · your Notes and Murmurs',
                        ),
                        active: page < 0.5,
                        showMark: page < 0.5,
                        underlineOpacity: (1 - page).clamp(0.0, 1.0),
                        textColor: Color.lerp(fgColor, faintColor, page)!,
                        ochreColor: ochreColor,
                      ),
                      const SizedBox(width: 32),
                      _boardButton(
                        board: _Board.forum,
                        label: context.uiCopy(zh: '討論區', en: 'Forum'),
                        tooltip: context.uiCopy(
                          zh: '討論區 · 追蹤的人與板',
                          en: 'Forum · follows and boards',
                        ),
                        active: page >= 0.5,
                        showMark: false,
                        underlineOpacity: page.clamp(0.0, 1.0),
                        textColor: Color.lerp(faintColor, fgColor, page)!,
                        ochreColor: ochreColor,
                      ),
                    ],
                  ),
                  if (onOpenPreferences != null || onOpenSettings != null)
                    Positioned(
                      right: 0,
                      top: -4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onOpenPreferences != null)
                            IconButton(
                              key: const Key('screen_style_button'),
                              onPressed: onOpenPreferences,
                              icon: const Icon(
                                Icons.palette_outlined,
                                size: 18,
                              ),
                              color: faintColor,
                              tooltip: context.uiCopy(
                                zh: '介面與動態',
                                en: 'Interface and motion',
                              ),
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 34,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          if (onOpenSettings != null)
                            IconButton(
                              key: const Key('settings_button'),
                              onPressed: onOpenSettings,
                              icon: const Icon(Icons.person_outline, size: 19),
                              color: faintColor,
                              tooltip: l10n.settingsNav,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 34,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: ruleColor, width: 0.5)),
                ),
                child: page < 0.5
                    ? _personalMetaRow(
                        context: context,
                        fgColor: fgColor,
                        mutedColor: mutedColor,
                        faintColor: faintColor,
                        surfaceColor: surfaceColor,
                        ruleColor: ruleColor,
                        ochreColor: ochreColor,
                      )
                    : _forumMetaRow(
                        context: context,
                        fgColor: fgColor,
                        mutedColor: mutedColor,
                        faintColor: faintColor,
                        surfaceColor: surfaceColor,
                        ruleColor: ruleColor,
                        ochreColor: ochreColor,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _boardButton({
    required _Board board,
    required String label,
    required String tooltip,
    required bool active,
    required bool showMark,
    required double underlineOpacity,
    required Color textColor,
    required Color ochreColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: active,
        label: tooltip,
        child: InkWell(
          key: Key('board_switch_${board.name}'),
          onTap: () => onTapBoard(board),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showMark) ...[
                      AnsibleMark(size: 13, color: textColor),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                        color: textColor,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: underlineOpacity,
                  child: Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      color: ochreColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personalMetaRow({
    required BuildContext context,
    required Color fgColor,
    required Color mutedColor,
    required Color faintColor,
    required Color surfaceColor,
    required Color ruleColor,
    required Color ochreColor,
  }) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(
            _todayLabel(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              letterSpacing: 1,
              color: faintColor,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FocusHeaderChip(
                label: l10n.searchScopeAll,
                selected: personalFilter == _PersonalFilter.all,
                onTap: () => onPersonalFilterChanged(_PersonalFilter.all),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
              _FocusHeaderChip(
                label: 'murmur',
                selected: personalFilter == _PersonalFilter.murmur,
                onTap: () => onPersonalFilterChanged(_PersonalFilter.murmur),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
              _FocusHeaderChip(
                label: 'note',
                selected: personalFilter == _PersonalFilter.note,
                onTap: () => onPersonalFilterChanged(_PersonalFilter.note),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _forumMetaRow({
    required BuildContext context,
    required Color fgColor,
    required Color mutedColor,
    required Color faintColor,
    required Color surfaceColor,
    required Color ruleColor,
    required Color ochreColor,
  }) {
    final l10n = context.l10n;
    final activeFilter = feedFilter == FeedFilter.boards
        ? FeedFilter.boards
        : FeedFilter.following;
    return Row(
      children: [
        Expanded(
          child: Text(
            context.uiCopy(
              zh: '$forumPostCount 新 · 今',
              en: '$forumPostCount new · today',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              letterSpacing: 1,
              color: faintColor,
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FocusHeaderChip(
                label: l10n.feedFollowing,
                selected: activeFilter == FeedFilter.following,
                onTap: () => onFeedFilterChanged(FeedFilter.following),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
              _FocusHeaderChip(
                label: l10n.feedBoards,
                selected: activeFilter == FeedFilter.boards,
                onTap: () => onFeedFilterChanged(FeedFilter.boards),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final weekday = weekdays[now.weekday - 1];
    return '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} $weekday';
  }
}

class _FocusHeaderChip extends StatelessWidget {
  const _FocusHeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.fgColor,
    required this.mutedColor,
    required this.surfaceColor,
    required this.ruleColor,
    required this.ochreColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color fgColor;
  final Color mutedColor;
  final Color surfaceColor;
  final Color ruleColor;
  final Color ochreColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? surfaceColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? ruleColor : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 11.5,
              color: selected ? fgColor : mutedColor,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// First-launch swipe coachmark overlay (F·10).
class _SwipeCoachmark extends StatefulWidget {
  const _SwipeCoachmark({required this.onDismiss});
  final VoidCallback onDismiss;
  @override
  State<_SwipeCoachmark> createState() => _SwipeCoachmarkState();
}

class _SwipeCoachmarkState extends State<_SwipeCoachmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _handCtrl;
  late final Animation<double> _handX;

  @override
  void initState() {
    super.initState();
    _handCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _handX = Tween<double>(
      begin: 0,
      end: 24,
    ).animate(CurvedAnimation(parent: _handCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _handCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
    final bgColor = dark
        ? AnsibleDesign.darkPaperElev
        : AnsibleDesign.paperElev;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final faintColor = dark
        ? AnsibleDesign.darkInkFaint
        : AnsibleDesign.inkFaint;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ochreColor.withValues(alpha: 0.55),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _handX,
                  builder: (context, _) => Transform.translate(
                    offset: Offset(_handX.value, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          color: ochreColor,
                          size: 28,
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: ochreColor,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.uiCopy(
                    zh: '這裡是你的個人版。',
                    en: 'This is your personal board.',
                  ),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: inkColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.uiCopy(
                    zh: '想看別人？往左滑，或是點上面的「討論區」。',
                    en: 'Want to see others? Swipe left or tap Forum above.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: faintColor,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onDismiss,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: faintColor,
                          side: BorderSide(
                            color: ochreColor.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(context.uiCopy(zh: '知道了', en: 'Got it')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: widget.onDismiss,
                        style: FilledButton.styleFrom(
                          backgroundColor: ochreColor,
                          foregroundColor: AnsibleDesign.paper,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          context.uiCopy(zh: '試試看·滑一下', en: 'Try swiping'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen Circle (圈內) pushed via Navigator for compose flows.
class _CircleFullScreen extends StatefulWidget {
  const _CircleFullScreen({
    required this.did,
    required this.db,
    required this.initialTab,
    required this.contentItems,
    required this.contentItemRepository,
    required this.murmurReferenceCounts,
    required this.onContentItemsChanged,
    required this.onPublishContentItem,
    required this.onSummonAiForNote,
    required this.openNoteEditorOnStart,
  });

  final String did;
  final AppDatabase db;
  final _CircleTab initialTab;
  final List<ContentItem> contentItems;
  final ContentItemRepository contentItemRepository;
  final Map<String, int> murmurReferenceCounts;
  final Future<void> Function() onContentItemsChanged;
  final Future<void> Function(ContentItem, DistributionPreference)
  onPublishContentItem;
  final Future<void> Function({
    String? noteId,
    String? noteTitle,
    String? noteBody,
  })
  onSummonAiForNote;
  final bool openNoteEditorOnStart;

  @override
  State<_CircleFullScreen> createState() => _CircleFullScreenState();
}

class _CircleFullScreenState extends State<_CircleFullScreen> {
  late _CircleTab _tab;
  late List<ContentItem> _contentItems;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _contentItems = [...widget.contentItems];
  }

  Future<void> _handleContentItemsChanged() async {
    await widget.onContentItemsChanged();
    final latest = await widget.contentItemRepository.list(
      authorDid: widget.did,
    );
    if (!mounted) return;
    setState(() => _contentItems = latest);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                    onPressed: () => Navigator.pop(context),
                    color: dark ? AnsibleDesign.darkInk : AnsibleDesign.ink,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tab == _CircleTab.murmur ? 'Murmur' : 'Note',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: dark
                                ? AnsibleDesign.darkInk
                                : AnsibleDesign.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tab == _CircleTab.murmur
                              ? context.uiCopy(
                                  zh: '說一段不用想太完整的話',
                                  en: 'Say something unfinished',
                                )
                              : context.uiCopy(
                                  zh: '個人版 · note',
                                  en: 'Personal · note',
                                ),
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9.5,
                            letterSpacing: 1.2,
                            color: dark
                                ? AnsibleDesign.darkInkFaint
                                : AnsibleDesign.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: switch (_tab) {
                  _CircleTab.murmur => MurmurScreen(
                    authorDid: widget.did,
                    contentItemRepository: widget.contentItemRepository,
                    recentMurmurs: _contentItems
                        .where((i) => i.mode == ContentMode.murmur)
                        .toList(),
                    murmurReferenceCounts: widget.murmurReferenceCounts,
                    onSaved: _handleContentItemsChanged,
                    onPublishContentItem: widget.onPublishContentItem,
                  ),
                  _CircleTab.notes => NoteWorkspaceScreen(
                    authorDid: widget.did,
                    notes: _contentItems
                        .where((i) => i.mode == ContentMode.note)
                        .toList(),
                    murmurs: _contentItems
                        .where((i) => i.mode == ContentMode.murmur)
                        .toList(),
                    contentItemRepository: widget.contentItemRepository,
                    onContentItemsChanged: _handleContentItemsChanged,
                    onPublishContentItem: widget.onPublishContentItem,
                    onSummonAI: ({noteId, noteTitle, noteBody}) =>
                        widget.onSummonAiForNote(
                          noteId: noteId,
                          noteTitle: noteTitle,
                          noteBody: noteBody,
                        ),
                    openCreateEditorOnStart: widget.openNoteEditorOnStart,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkStatusIndicator extends StatelessWidget {
  const _NetworkStatusIndicator({
    required this.status,
    required this.connectionType,
    this.compact = false,
    this.onTap,
  });

  final NetworkStatus status;
  final String connectionType;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    IconData icon;
    Color color;
    String tooltip;
    String label;

    switch (status) {
      case NetworkStatus.online:
        icon = Icons.wifi_rounded;
        color = Colors.green;
        label = connectionType;
        tooltip = '${l10n.networkOnline} · $connectionType';
        break;
      case NetworkStatus.offline:
        icon = Icons.wifi_off_rounded;
        color = Colors.red;
        label = l10n.networkOffline;
        tooltip = l10n.networkOffline;
        break;
      case NetworkStatus.checking:
        icon = Icons.wifi_find_rounded;
        color = Colors.orange;
        label = l10n.networkChecking;
        tooltip = l10n.networkChecking;
        break;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: compact
              ? _NetworkStatusGlyph(icon: icon, color: color)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NetworkStatusGlyph(icon: icon, color: color),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NetworkStatusGlyph extends StatelessWidget {
  const _NetworkStatusGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 16, color: color);
  }
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
    required this.reactions,
    required this.comments,
    required this.reacted,
    this.authorTier = 'basic',
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
                    child: Text(
                      data.author,
                      style: const TextStyle(color: AnsibleDesign.inkMuted),
                    ),
                  ),
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
