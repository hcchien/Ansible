import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../config/app_environment.dart';
import '../../l10n/app_l10n.dart';
import '../../services/discovery_client.dart';
import '../../services/ops_dispatch_service.dart';
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
  });

  final AppDatabase db;
  final String did;
  final bool loading;
  final List<PostCardData> followingPosts;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;

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
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
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

  Widget _timelineEmptyState(BuildContext context) {
    final style = ElixScreenStyleScope.dataOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.uiCopy(
                zh: '還沒有追蹤任何人',
                en: 'You are not following anyone yet',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: style.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.uiCopy(
                zh: '到「探索」找人追蹤，他們的貼文會出現在這裡。',
                en: 'Find people in Discover — their posts will appear here.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: style.muted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DiscoverScreen(
                      db: db,
                      localDid: did,
                      client: DiscoveryClient(
                        appViewBaseUrl: AppEnvironment.appViewBaseUrl,
                        relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: Text(context.uiCopy(zh: '探索', en: 'Discover')),
            ),
          ],
        ),
      ),
    );
  }
}
