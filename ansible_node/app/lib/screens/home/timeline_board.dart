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
    this.onCompose,
  });

  final AppDatabase db;
  final String did;
  final bool loading;
  final List<PostCardData> followingPosts;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;

  /// Opens the compose sheet (guided first session step 3); when null the
  /// step still renders but points at the bottom-bar ＋.
  final VoidCallback? onCompose;

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
                  itemBuilder: (context, index) => PostCard(
                    db: db,
                    data: followingPosts[index],
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
                            screenStyle: ElixScreenStyleScope.styleOf(context),
                          ),
                        ),
                      );
                    },
                  ),
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

    void openDiscover({required bool boards}) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 24),
      children: [
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
          onTap: () => openDiscover(boards: true),
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
          onTap: () => openDiscover(boards: false),
        ),
      ],
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
