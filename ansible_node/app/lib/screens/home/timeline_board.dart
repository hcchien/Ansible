import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../config/app_environment.dart';
import '../../l10n/app_l10n.dart';
import '../../services/discovery_client.dart';
import '../../services/ops_dispatch_service.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../content_detail_screen.dart';
import '../discover_screen.dart';
import '../user_profile_screen.dart';
import 'post_card.dart';
import 'home_types.dart';

/// Timeline board (時間軸) — posts from people you follow.
class TimelineBoardView extends StatelessWidget {
  const TimelineBoardView({
    super.key,
    required this.db,
    required this.did,
    required this.loading,
    required this.followingPosts,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    required this.onOpenBoard,
    this.onCompose,
    this.sort = TimelineSort.newest,
    this.onSortChanged,
  });

  final AppDatabase db;
  final String did;
  final bool loading;
  final List<PostCardData> followingPosts;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;
  final ValueChanged<String> onOpenBoard;

  /// Opens the compose sheet (guided first session step 3); when null the
  /// step still renders but points at the bottom-bar ＋.
  final VoidCallback? onCompose;
  final TimelineSort sort;
  final ValueChanged<TimelineSort>? onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : followingPosts.isEmpty
              ? _timelineEmptyState(context)
              : ListView.separated(
                  itemCount: followingPosts.length,
                  padding: const EdgeInsets.only(bottom: 12),
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final post = followingPosts[index];
                    return PostCard(
                      db: db,
                      data: post,
                      authorDid: did,
                      opsDispatchService: opsDispatchService,
                      onFlushPendingOps: onFlushPendingOps,
                      onOpenAuthor: (authorDid) {
                        if (authorDid.isEmpty) return;
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
                      onOpenBoard: onOpenBoard,
                      onOpenContent: (data) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ContentDetailScreen(
                              db: db,
                              localDid: did,
                              contentId: data.thread.id,
                              authorDid: data.author,
                              body: data.content,
                              title: data.title,
                              timeAgo: data.timeAgo,
                              opsDispatchService: opsDispatchService,
                              onFlushPendingOps: onFlushPendingOps,
                              // Carry the feed's Paper/Ink choice into the detail.
                              screenStyle: ElixScreenStyleScope.styleOf(
                                context,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // A genuinely empty dynamic wall stays lightweight. Discovery and compose
  // remain available as actions, but onboarding copy must not masquerade as
  // fixed feed content on every fresh account.
  Widget _timelineEmptyState(BuildContext context) {
    final style = ElixScreenStyleScope.dataOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 24),
      children: [
        _sortControl(context, style),
        const SizedBox(height: 12),
        _discoveryEntry(context, style),
        const SizedBox(height: 24),
        Text(
          context.uiCopy(zh: '動態牆還沒有內容', en: 'Your feed is empty'),
          style: TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: style.foreground,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.uiCopy(
            zh: '追蹤使用者或看板後，新的公開內容會出現在這裡。',
            en: 'Follow people or boards and their new public posts appear here.',
          ),
          style: TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 14.5,
            height: 1.7,
            color: style.muted,
          ),
        ),
        const SizedBox(height: 20),
        _guideStep(
          context,
          style: style,
          key: const Key('first_session_step_boards'),
          number: '',
          icon: Icons.dashboard_outlined,
          title: context.uiCopy(zh: '訂閱一個看板', en: 'Subscribe to a board'),
          subtitle: context.uiCopy(
            zh: '尋找公開討論。',
            en: 'Find public discussions.',
          ),
          onTap: () => _openDiscover(context, boards: true),
        ),
        _guideStep(
          context,
          style: style,
          key: const Key('first_session_step_people'),
          number: '',
          icon: Icons.person_add_alt_outlined,
          title: context.uiCopy(zh: '追蹤一個人', en: 'Follow someone'),
          subtitle: context.uiCopy(
            zh: '從公開使用者目錄開始。',
            en: 'Browse the public people directory.',
          ),
          onTap: () => _openDiscover(context, boards: false),
        ),
      ],
    );
  }

  Widget _sortControl(BuildContext context, ElixScreenStyleData style) {
    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<TimelineSort>(
        key: const Key('timeline_sort_menu'),
        initialValue: sort,
        onSelected: onSortChanged,
        color: style.surface,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: TimelineSort.newest,
            child: Text(context.uiCopy(zh: '最新優先', en: 'Newest first')),
          ),
          PopupMenuItem(
            value: TimelineSort.oldest,
            child: Text(context.uiCopy(zh: '最舊優先', en: 'Oldest first')),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_vert, size: 18, color: style.muted),
              const SizedBox(width: 5),
              Text(
                sort == TimelineSort.newest
                    ? context.uiCopy(zh: '最新優先', en: 'Newest first')
                    : context.uiCopy(zh: '最舊優先', en: 'Oldest first'),
                style: TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  fontSize: 13,
                  color: style.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDiscover(BuildContext context, {bool boards = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoverScreen(
          db: db,
          localDid: did,
          startOnBoards: boards,
          client: DiscoveryClient(
            appViewBaseUrl: AppEnvironment.appViewBaseUrl,
            relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
          ),
        ),
      ),
    );
  }

  Widget _discoveryEntry(BuildContext context, ElixScreenStyleData style) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Material(
        color: AnsibleDesign.ochre.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const Key('timeline_discovery_entry'),
          onTap: () => _openDiscover(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AnsibleDesign.ochre, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AnsibleDesign.ochre,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.explore_outlined,
                    color: AnsibleDesign.ink,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.uiCopy(zh: '探索 Elix', en: 'Discover Elix'),
                        style: TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: style.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.uiCopy(
                          zh: '尋找使用者、看板與公開貼文',
                          en: 'Find people, boards, and public posts',
                        ),
                        style: TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 13,
                          color: style.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: style.foreground, size: 21),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guideStep(
    BuildContext context, {
    required ElixScreenStyleData style,
    required Key key,
    required String number,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: style.rule, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: style.rule, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 19, color: style.muted),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      number.isEmpty ? title : '$number · $title',
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: style.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        height: 1.5,
                        color: style.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: style.faint),
            ],
          ),
        ),
      ),
    );
  }
}
