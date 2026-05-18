import 'dart:async';
import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../widgets/board_form_dialog.dart';
import '../widgets/thread_form_dialog.dart';
import '../services/atproto_client.dart';
import '../services/ai/ai_provider_config_store.dart';
import '../services/app_locale_controller.dart';
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
import '../services/relay_ops_client.dart';
import '../widgets/ai_provider_setup_sheet.dart';
import '../widgets/feed_filter_tabs.dart';
import '../widgets/ops_queue_status_badge.dart';
import '../widgets/transformation_review_sheet.dart';
import 'murmur_screen.dart';
import 'note_editor_screen.dart';
import 'note_workspace_screen.dart';
import 'posts_view_screen.dart';
import 'contact_picker_screen.dart' show ContactInputResolver;
import 'inbox_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'settings_home_screen.dart';
import 'wallet_screen.dart';
import 'package:ansible_store/ansible_store.dart' as store;
import '../theme/ansible_design.dart';

/// Focus Mode rooms — replaces the old flat tab model.
enum _ElixRoom { personal, plaza, circle }

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
    this.networkStatusMonitor,
    this.localeController,
  });

  final AppDatabase db;
  final String did;
  final VoidCallback? onClearIdentity;
  final Future<AppSyncResult> Function()? syncRunner;
  final Future<RelayPullSummary> Function()? pullRefreshRunner;
  final NetworkStatusMonitor? networkStatusMonitor;
  final AppLocaleController? localeController;

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
  late final DriftContentRelationRepository _contentRelationRepo;
  late final DriftPublicationRepository _publicationRepo;
  late final DriftForumHostRepository _forumHostRepo;
  late final DriftHostedBoardRepository _hostedBoardRepo;
  late final DriftAiProviderConfigRepository _aiProviderConfigRepo;
  late final AiProviderConfigStore _aiProviderConfigStore;
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
  NetworkStatus? _lastNetworkStatus;
  DateTime? _lastAutoSyncAt;
  String? _selectedBoardId;
  FeedFilter _feedFilter = FeedFilter.all;
  _ElixRoom _selectedRoom = _ElixRoom.personal;
  _CircleTab _selectedCircleTab = _CircleTab.murmur;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
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
    _contentRelationRepo = DriftContentRelationRepository(widget.db);
    _publicationRepo = DriftPublicationRepository(widget.db);
    _forumHostRepo = DriftForumHostRepository(widget.db);
    _hostedBoardRepo = DriftHostedBoardRepository(widget.db);
    _aiProviderConfigRepo = DriftAiProviderConfigRepository(widget.db);
    _aiProviderConfigStore = AiProviderConfigStore(
      repository: _aiProviderConfigRepo,
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
      unawaited(_loadData());
      unawaited(_runForegroundPullIfConfigured());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkStatusService.removeListener(_handleNetworkStatusChanged);
    if (_ownsNetworkStatusService) {
      _networkStatusService.dispose();
    }
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
    final hasActiveRelay = (await _forumHostRepo.listActive()).isNotEmpty;
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
        ? await FollowFeedProjector(
            followRepository: _followRepo,
            boardRepository: _boardRepo,
            threadRepository: _threadRepo,
            postRepository: _postRepo,
          ).project(followerDid: widget.did)
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

    setState(() {
      _boards = boards;
      _posts = postCards;
      _contentItems = contentItems;
      _murmurReferenceCounts = murmurReferenceCounts;
      _hasActiveMessengerRelay = hasActiveRelay;
      _loading = false;
    });
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

  void _selectRoom(_ElixRoom room) {
    setState(() => _selectedRoom = room);
  }

  void _selectCircleTab(_CircleTab tab) {
    setState(() => _selectedCircleTab = tab);
  }

  Future<void> _startAiTransformation() async {
    final providers = await _aiProviderConfigRepo.list();
    if (!mounted) return;
    if (providers.isEmpty) {
      final result = await showModalBottomSheet<AiProviderSetupResult>(
        context: context,
        backgroundColor: AnsibleDesign.paper,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const AiProviderSetupSheet(),
      );
      if (result == null) return;
      await _aiProviderConfigStore.save(
        displayName: result.displayName,
        providerType: result.providerType,
        baseUrl: result.baseUrl,
        modelName: result.modelName,
        apiKey: result.apiKey,
        defaultForTransformations: true,
        defaultForSummaries: true,
      );
      if (!mounted) return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TransformationReviewSheet(
        title: 'Draft note',
        body: 'Review AI output before it becomes local content.',
        sourceLabels: const ['Current workspace'],
        containsPrivateSource: true,
        onAccept: (title, body) async {
          final now = DateTime.now().toUtc();
          await _contentItemRepo.create(
            ContentItem(
              id: _uuid.v4(),
              authorDid: widget.did,
              mode: ContentMode.note,
              title: title,
              body: body,
              status: ContentStatus.active,
              visibility: ContentVisibility.private,
              createdAt: now,
              updatedAt: now,
            ),
          );
        },
      ),
    );
  }

  Future<List<PostCardData>> _buildFollowingPostCards(
    List<FollowFeedEntry> entries,
    Map<String, Board> boardMap,
  ) async {
    final cards = <PostCardData>[];
    final l10n = context.l10n;
    for (final entry in entries) {
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
    final signature = await DidSignerImpl()
        .sign(utf8.encode('$intentId:${widget.did}:$title'))
        .then((signature) => signature.hex);
    final remoteBoard = await ForumHostClient(baseUrl: forumHost.url)
        .createHostedBoard(
          CreateHostedBoardIntent(
            intentId: intentId,
            authorDid: widget.did,
            signature: signature,
            title: title,
            description: result['description'],
          ),
        );
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
    return Scaffold(
      body: SafeArea(
        child: Container(
          color: AnsibleDesign.paper,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final mainPanel = _MainPanel(
                db: widget.db,
                did: widget.did,
                localeController: widget.localeController,
                opsQueueRepo: _opsQueueRepo,
                opsDispatchService: _opsDispatchService,
                messengerSyncService: _messengerSyncService,
                contactAvailabilityResolver:
                    _messengerContactResolver.resolveAvailability,
                contactInputResolver: _contactResolver.resolveInput,
                hasActiveRelay: _hasActiveMessengerRelay,
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
                hasSelectedBoard: _selectedBoardId != null,
                selectedBoardId: _selectedBoardId,
                boards: _boards,
                networkStatusService: _networkStatusService,
                selectedRoom: _selectedRoom,
                onRoomChanged: _selectRoom,
                selectedCircleTab: _selectedCircleTab,
                onCircleTabChanged: _selectCircleTab,
                contentItemRepository: _contentItemRepo,
                contentItems: _contentItems,
                murmurReferenceCounts: _murmurReferenceCounts,
                onContentItemsChanged: _loadData,
                onPublishContentItem: _publishContentItem,
                onStartAiAction: _startAiTransformation,
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
    required this.opsQueueRepo,
    required this.opsDispatchService,
    required this.messengerSyncService,
    required this.contactAvailabilityResolver,
    required this.contactInputResolver,
    required this.hasActiveRelay,
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
    required this.hasSelectedBoard,
    required this.selectedBoardId,
    required this.boards,
    required this.networkStatusService,
    required this.selectedRoom,
    required this.onRoomChanged,
    required this.selectedCircleTab,
    required this.onCircleTabChanged,
    required this.contentItemRepository,
    required this.contentItems,
    required this.murmurReferenceCounts,
    required this.onContentItemsChanged,
    required this.onPublishContentItem,
    required this.onStartAiAction,
  });

  final VoidCallback? onClearIdentity;
  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final OpsQueueRepository opsQueueRepo;
  final OpsDispatchService opsDispatchService;
  final MessengerSyncService messengerSyncService;
  final ContactAvailabilityResolver contactAvailabilityResolver;
  final ContactInputResolver contactInputResolver;
  final bool hasActiveRelay;
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
  final bool hasSelectedBoard;
  final String? selectedBoardId;
  final List<Board> boards;
  final NetworkStatusMonitor networkStatusService;
  final _ElixRoom selectedRoom;
  final ValueChanged<_ElixRoom> onRoomChanged;
  final _CircleTab selectedCircleTab;
  final ValueChanged<_CircleTab> onCircleTabChanged;
  final ContentItemRepository contentItemRepository;
  final List<ContentItem> contentItems;
  final Map<String, int> murmurReferenceCounts;
  final Future<void> Function() onContentItemsChanged;
  final Future<void> Function(ContentItem, DistributionPreference)
  onPublishContentItem;
  final Future<void> Function() onStartAiAction;

  // ── Room label helpers ────────────────────────────────────────────────────
  String _roomLabel(_ElixRoom room) {
    switch (room) {
      case _ElixRoom.personal:
        return '個人版';
      case _ElixRoom.plaza:
        return '廣場';
      case _ElixRoom.circle:
        return '圈內';
    }
  }

  List<ElixRoomItem> _roomItems(_ElixRoom current) {
    return [
      ElixRoomItem(id: 'personal', label: '個人版', active: current == _ElixRoom.personal),
      ElixRoomItem(id: 'plaza', label: '廣場', active: current == _ElixRoom.plaza),
      ElixRoomItem(id: 'circle', label: '圈內', active: current == _ElixRoom.circle),
      const ElixRoomItem(id: 'settings', label: '設定'),
    ];
  }

  void _handleRoomSelected(String id, BuildContext context) {
    switch (id) {
      case 'personal':
        onRoomChanged(_ElixRoom.personal);
      case 'plaza':
        onRoomChanged(_ElixRoom.plaza);
      case 'circle':
        onRoomChanged(_ElixRoom.circle);
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsHomeScreen(
              db: db,
              did: did,
              localeController: localeController,
              onClearIdentity: onClearIdentity,
            ),
          ),
        );
    }
  }

  // ── Personal board (個人版) ─────────────────────────────────────────────
  Widget _buildPersonalBoard(BuildContext context, bool compact) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final faintColor = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    final borderColor = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final fillColor = dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;

    // Sort contentItems by most recent
    final sorted = [...contentItems]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    String timeAgo(DateTime dt) {
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '剛剛';
      if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
      if (diff.inDays < 1) return '${diff.inHours} 小時前';
      return '${diff.inDays} 天前';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compose prompt
        GestureDetector(
          onTap: () {
            onRoomChanged(_ElixRoom.circle);
            onCircleTabChanged(_CircleTab.murmur);
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '今天想記錄什麼？',
                    style: TextStyle(
                      fontSize: 15,
                      color: faintColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                Icon(Icons.edit_outlined, size: 18, color: faintColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (sorted.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                '還沒有任何記錄',
                style: TextStyle(
                  fontSize: 15,
                  color: mutedColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = sorted[index];
                final kind = item.mode == ContentMode.murmur ? 'murmur' : 'note';
                final title = item.title ?? '';
                final preview = item.body.replaceAll('\n', ' ');
                return DiaryEntryCard(
                  kind: kind,
                  title: title,
                  preview: preview.isEmpty ? '（無內容）' : preview,
                  timeAgo: timeAgo(item.createdAt),
                  onTap: () {
                    // Navigate to circle → correct tab
                    onRoomChanged(_ElixRoom.circle);
                    onCircleTabChanged(
                      item.mode == ContentMode.murmur
                          ? _CircleTab.murmur
                          : _CircleTab.notes,
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  // ── Plaza board (廣場) ──────────────────────────────────────────────────
  Widget _buildPlaza(BuildContext context, bool compact) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FeedFilterTabs(
          selected: feedFilter,
          onChanged: onFeedFilterChanged,
        ),
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
                              threadTitle: boards
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
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : posts.isEmpty
              ? Center(
                  child: Text(
                    l10n.noPostsYet,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AnsibleDesign.inkMuted),
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
                  ),
                ),
        ),
      ],
    );
  }

  // ── Inner circle (圈內) ─────────────────────────────────────────────────
  Widget _buildCircle(BuildContext context) {
    return Column(
      children: [
        // Sub-tab: Murmur / Notes
        _CircleTabNav(
          selected: selectedCircleTab,
          onChanged: onCircleTabChanged,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (selectedCircleTab) {
            _CircleTab.murmur => MurmurScreen(
              authorDid: did,
              contentItemRepository: contentItemRepository,
              recentMurmurs: contentItems
                  .where((item) => item.mode == ContentMode.murmur)
                  .toList(),
              murmurReferenceCounts: murmurReferenceCounts,
              onSaved: onContentItemsChanged,
              onPublishContentItem: onPublishContentItem,
            ),
            _CircleTab.notes => NoteWorkspaceScreen(
              authorDid: did,
              notes: contentItems
                  .where((item) => item.mode == ContentMode.note)
                  .toList(),
              murmurs: contentItems
                  .where((item) => item.mode == ContentMode.murmur)
                  .toList(),
              contentItemRepository: contentItemRepository,
              onContentItemsChanged: onContentItemsChanged,
              onPublishContentItem: onPublishContentItem,
            ),
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final contentPadding = compact
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 28, vertical: 12);

        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(
                  onClearIdentity: onClearIdentity,
                  db: db,
                  did: did,
                  localeController: localeController,
                  opsQueueRepo: opsQueueRepo,
                  onSync: onSync,
                  syncing: syncing,
                  networkStatusService: networkStatusService,
                  contentItems: contentItems,
                  messengerSyncService: messengerSyncService,
                  contactAvailabilityResolver: contactAvailabilityResolver,
                  contactInputResolver: contactInputResolver,
                  hasActiveRelay: hasActiveRelay,
                ),
                Expanded(
                  child: Padding(
                    padding: contentPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Room header ───────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ElixRoomHeader(
                              roomLabel: _roomLabel(selectedRoom),
                              rooms: _roomItems(selectedRoom),
                              onRoomSelected: (id) =>
                                  _handleRoomSelected(id, context),
                            ),
                            const Spacer(),
                            if (selectedRoom == _ElixRoom.plaza &&
                                onOpenBoards != null)
                              IconButton(
                                onPressed: onOpenBoards,
                                icon: const Icon(Icons.view_sidebar_outlined),
                                color: AnsibleDesign.inkMuted,
                                tooltip: '訂閱版塊',
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Room body ─────────────────────────────────────
                        Expanded(
                          child: switch (selectedRoom) {
                            _ElixRoom.personal =>
                              _buildPersonalBoard(context, compact),
                            _ElixRoom.plaza => _buildPlaza(context, compact),
                            _ElixRoom.circle => _buildCircle(context),
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Floating AI dot ───────────────────────────────────────────
            Positioned(
              right: 16,
              bottom: 88,
              child: ElixAIDot(onTap: onStartAiAction),
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    this.onClearIdentity,
    required this.db,
    required this.did,
    this.localeController,
    required this.opsQueueRepo,
    required this.onSync,
    required this.syncing,
    required this.networkStatusService,
    required this.contentItems,
    required this.messengerSyncService,
    required this.contactAvailabilityResolver,
    required this.contactInputResolver,
    required this.hasActiveRelay,
  });

  final VoidCallback? onClearIdentity;
  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final OpsQueueRepository opsQueueRepo;
  final Future<void> Function() onSync;
  final bool syncing;
  final NetworkStatusMonitor networkStatusService;
  final List<ContentItem> contentItems;
  final MessengerSyncService messengerSyncService;
  final ContactAvailabilityResolver contactAvailabilityResolver;
  final ContactInputResolver contactInputResolver;
  final bool hasActiveRelay;

  String get _truncatedDid {
    if (did.length <= 24) return did;
    return '${did.substring(0, 18)}...${did.substring(did.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
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
                color: AnsibleDesign.inkMuted,
                tooltip: l10n.search,
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InboxScreen(
                        repository: DriftMessengerRepository(db),
                        contactRepository: DriftContactRepository(db),
                        messengerService: messengerSyncService,
                        senderDid: did,
                        relayConfigured: hasActiveRelay,
                        resolveContactAvailability: contactAvailabilityResolver,
                        resolveContactInput: contactInputResolver,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.inbox_outlined),
                color: AnsibleDesign.inkMuted,
                tooltip: l10n.inbox,
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
                      const Icon(
                        Icons.fingerprint,
                        size: 16,
                        color: AnsibleDesign.accent,
                      ),
                      const SizedBox(width: 6),
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
                color: AnsibleDesign.inkMuted,
                tooltip: l10n.sync,
              ),
              if (!compact)
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(did: did),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline),
                  color: AnsibleDesign.inkMuted,
                  tooltip: l10n.publicIdentity,
                ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsHomeScreen(
                        db: db,
                        did: did,
                        localeController: localeController,
                        onClearIdentity: onClearIdentity,
                      ),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.settings_outlined,
                  color: AnsibleDesign.inkMuted,
                ),
                tooltip: l10n.settingsNav,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Sub-navigation inside the 圈內 room: Murmur vs Notes.
class _CircleTabNav extends StatelessWidget {
  const _CircleTabNav({required this.selected, required this.onChanged});

  final _CircleTab selected;
  final ValueChanged<_CircleTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<_CircleTab>(
      style: SegmentedButton.styleFrom(
        backgroundColor: AnsibleDesign.paper,
        selectedBackgroundColor: AnsibleDesign.paperDeep,
        foregroundColor: AnsibleDesign.inkMuted,
        selectedForegroundColor: AnsibleDesign.ink,
        side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
      ),
      segments: [
        ButtonSegment(
          value: _CircleTab.murmur,
          icon: const Icon(Icons.chat_bubble_outline, size: 18),
          label: Text(l10n.murmurTab, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        ButtonSegment(
          value: _CircleTab.notes,
          icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
          label: Text(l10n.notesTab, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.single),
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
}

class PostCard extends StatefulWidget {
  const PostCard({
    super.key,
    required this.data,
    required this.db,
    required this.authorDid,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
  });

  final AppDatabase db;
  final PostCardData data;
  final String authorDid;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;

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
                  Text(
                    data.author,
                    style: const TextStyle(color: AnsibleDesign.inkMuted),
                  ),
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
