import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../services/app_locale_controller.dart';
import '../../services/atproto_client.dart';
import '../../services/messenger_sync_service.dart';
import '../../services/network_status_service.dart';
import '../../services/ops_dispatch_service.dart';
import '../../services/handle_resolver.dart';
import '../../services/reading_preferences_controller.dart';
import '../../services/relay_discovery_client.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/feed_filter_tabs.dart';
import '../contact_picker_screen.dart' show ContactInputResolver;
import '../inbox_screen.dart' show ContactAvailabilityResolver;
import '../search_screen.dart';
import '../settings_home_screen.dart';
import 'board_swipe.dart';
import 'board_swipe_header.dart';
import 'forum_board.dart';
import 'home_types.dart';
import 'personal_board.dart';
import 'post_card.dart';
import 'swipe_coachmark.dart';
import 'timeline_board.dart';
import 'top_bar.dart';

class MainPanel extends StatelessWidget {
  const MainPanel({
    super.key,
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
    this.notificationUnreadCount = 0,
    this.onOpenNotifications,
    required this.atProtoClient,
    required this.loading,
    required this.posts,
    required this.followingPosts,
    required this.onRefresh,
    required this.onCreateThread,
    required this.onCreateBoard,
    required this.onManageBoards,
    required this.onDiscoverBoards,
    required this.onOpenBoard,
    this.onOpenBoards,
    this.bottomNav = false,
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

  /// Unread count for the notification bell (local notifications table).
  final int notificationUnreadCount;

  /// Opens the notification feed; when null the bell is hidden.
  final VoidCallback? onOpenNotifications;
  final AtProtoClient atProtoClient;
  final bool loading;
  final List<PostCardData> posts;
  final List<PostCardData> followingPosts;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateThread;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onManageBoards;
  final VoidCallback onDiscoverBoards;
  final ValueChanged<String> onOpenBoard;
  final VoidCallback? onOpenBoards;

  /// When true, the top board-switch tab row is hidden (navigation lives in the
  /// Scaffold's bottom bar instead).
  final bool bottomNav;
  final FeedFilter feedFilter;
  final ValueChanged<FeedFilter> onFeedFilterChanged;
  final PersonalFilter personalFilter;
  final ValueChanged<PersonalFilter> onPersonalFilterChanged;
  final bool hasSelectedBoard;
  final String? selectedBoardId;
  final List<Board> boards;
  final NetworkStatusMonitor networkStatusService;
  final PageController pageController;
  final ElixTab selectedTab;
  final ValueChanged<ElixTab> onTabChanged;
  final ValueChanged<int> onPageChanged;
  final HomeBoard selectedBoard;
  final ValueChanged<HomeBoard> onBoardChanged;
  final bool showCoachmark;
  final VoidCallback onDismissCoachmark;
  final void Function(BuildContext, CircleTab) onOpenCircle;
  final VoidCallback onComposeTap;
  final VoidCallback onScreenStyleTap;
  final ValueChanged<ElixScreenStyle> onPersonalScreenStyleChanged;
  final ValueChanged<ElixScreenStyle> onForumScreenStyleChanged;
  final ValueChanged<ElixBoardMotion> onBoardMotionChanged;
  final Map<ElixTab, ElixScreenStyle> screenStyles;
  final ElixBoardMotion boardMotion;
  final CircleTab selectedCircleTab;
  final ValueChanged<CircleTab> onCircleTabChanged;
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

  Widget _buildBoardSwiper(BuildContext context, bool compact) {
    final contentPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 28, vertical: 12);

    Widget wrapPage(ElixTab tab, Widget child, {String? scopeName}) {
      final style = screenStyles[tab] ?? ElixScreenStyle.paper;
      final data = style.dataFor(Theme.of(context).brightness);
      return ElixScreenStyleScope(
        style: style,
        child: AnimatedContainer(
          key: Key('screen_style_scope_${scopeName ?? tab.name}'),
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
            BoardFlipPage(
              key: const Key('board_swipe_page_transform_feed'),
              pageController: pageController,
              pageIndex: HomeBoard.personal.index,
              selectedBoard: selectedBoard,
              motion: boardMotion,
              child: wrapPage(
                ElixTab.feed,
                Padding(
                  padding: contentPadding,
                  child: PersonalBoardView(
                    loading: loading,
                    contentItems: contentItems,
                    personalFilter: personalFilter,
                    showFirstRunDiscovery: showFirstRunDiscovery,
                    firstRunDiscovery: firstRunDiscovery,
                    firstRunDiscoveryLoading: firstRunDiscoveryLoading,
                    onOpenDiscoveredForumHost: onOpenDiscoveredForumHost,
                    onOpenCircle: onOpenCircle,
                    onStartAiAction: onStartAiAction,
                    onComposeTap: onComposeTap,
                  ),
                ),
              ),
            ),
            BoardFlipPage(
              key: const Key('board_swipe_page_transform_timeline'),
              pageController: pageController,
              pageIndex: HomeBoard.timeline.index,
              selectedBoard: selectedBoard,
              motion: boardMotion,
              child: wrapPage(
                ElixTab.feed,
                scopeName: 'timeline',
                Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 14 : 28,
                    right: compact ? 14 : 28,
                    top: 12,
                  ),
                  child: TimelineBoardView(
                    db: db,
                    did: did,
                    loading: loading,
                    followingPosts: followingPosts,
                    opsDispatchService: opsDispatchService,
                    onFlushPendingOps: onFlushPendingOps,
                    onCompose: onComposeTap,
                  ),
                ),
              ),
            ),
            BoardFlipPage(
              key: const Key('board_swipe_page_transform_circle'),
              pageController: pageController,
              pageIndex: HomeBoard.forum.index,
              selectedBoard: selectedBoard,
              motion: boardMotion,
              child: wrapPage(
                ElixTab.circle,
                Padding(
                  padding: EdgeInsets.only(
                    left: compact ? 14 : 28,
                    right: compact ? 14 : 28,
                    top: 12,
                  ),
                  child: ForumBoardView(
                    compact: compact,
                    db: db,
                    did: did,
                    loading: loading,
                    posts: posts,
                    boards: boards,
                    selectedBoardId: selectedBoardId,
                    hasSelectedBoard: hasSelectedBoard,
                    atProtoClient: atProtoClient,
                    opsDispatchService: opsDispatchService,
                    onFlushPendingOps: onFlushPendingOps,
                    onCreateThread: onCreateThread,
                    onCreateBoard: onCreateBoard,
                    onManageBoards: onManageBoards,
                    onDiscoverBoards: onDiscoverBoards,
                    onOpenBoard: onOpenBoard,
                    showBottomActionBar: !bottomNav,
                  ),
                ),
              ),
            ),
          ],
        ),
        BoardSwipeProgressPill(
          pageController: pageController,
          compact: compact,
          motion: boardMotion,
        ),
      ],
    );
  }

  /// The Elix brand header shown on phone (b01 design): constellation mark +
  /// "Elix" wordmark on the left, search + passkey identity chip on the right.
  Widget _compactBrandHeader(BuildContext context) {
    final s = (screenStyles[selectedTab] ?? ElixScreenStyle.paper).dataFor(
      Theme.of(context).brightness,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 14, 12),
      color: s.background,
      child: Row(
        children: [
          AnsibleMark(size: 20, color: s.foreground),
          const SizedBox(width: 9),
          ElixWordmark(fontSize: 21, color: s.foreground),
          const Spacer(),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: s.surface, shape: BoxShape.circle),
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(contentItems: contentItems),
                ),
              ),
              icon: const Icon(Icons.search, size: 20),
              color: s.foreground,
              tooltip: context.uiCopy(zh: '搜尋', en: 'Search'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          _sessionChip(s),
        ],
      ),
    );
  }

  Widget _sessionChip(ElixScreenStyleData s) {
    return FutureBuilder<String?>(
      initialData: HandleResolver.shared.cached(did),
      future: HandleResolver.shared.handleFor(did),
      builder: (context, snap) {
        final h = (snap.data ?? '').replaceFirst('@', '').trim();
        final initial = h.isEmpty ? '·' : h.substring(0, 1).toUpperCase();
        return Container(
          padding: const EdgeInsets.fromLTRB(3, 3, 9, 3),
          decoration: BoxDecoration(
            border: Border.all(color: s.rule),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: s.background,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'PK',
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                  color: s.accent,
                ),
              ),
            ],
          ),
        );
      },
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
            // Phone: the design's clean "Elix" brand header (mark + wordmark +
            // search + identity chip) sits above the boards; navigation lives in
            // the bottom bar.
            if (compact) _compactBrandHeader(context),
            // The bottom nav (compact/phone) replaces the top header entirely;
            // gate on bottomNav too so the 640–720 band doesn't show both.
            if (!compact && !bottomNav)
              HomeTopBar(
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
                    screenStyles[ElixTab.feed] ?? ElixScreenStyle.ink,
                forumScreenStyle:
                    screenStyles[ElixTab.circle] ?? ElixScreenStyle.paper,
                boardMotion: boardMotion,
                onPersonalScreenStyleChanged: onPersonalScreenStyleChanged,
                onForumScreenStyleChanged: onForumScreenStyleChanged,
                onBoardMotionChanged: onBoardMotionChanged,
              ),
            if (!bottomNav)
              BoardSwipeHeader(
                showTabs: !bottomNav,
                pageController: pageController,
                selectedBoard: selectedBoard,
                onTapBoard: onBoardChanged,
                personalStyle:
                    screenStyles[ElixTab.feed] ?? ElixScreenStyle.ink,
                timelineStyle:
                    screenStyles[ElixTab.feed] ?? ElixScreenStyle.ink,
                forumStyle:
                    screenStyles[ElixTab.circle] ?? ElixScreenStyle.paper,
                personalFilter: personalFilter,
                onPersonalFilterChanged: onPersonalFilterChanged,
                feedFilter: feedFilter,
                onFeedFilterChanged: onFeedFilterChanged,
                forumPostCount: posts.length,
                notificationUnreadCount: notificationUnreadCount,
                onOpenNotifications: onOpenNotifications,
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
                                  screenStyles[ElixTab.feed] ??
                                  ElixScreenStyle.ink,
                              forumScreenStyle:
                                  screenStyles[ElixTab.circle] ??
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
                    SwipeCoachmark(onDismiss: onDismissCoachmark),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
