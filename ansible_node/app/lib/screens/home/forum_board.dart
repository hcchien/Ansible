import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../services/atproto_client.dart';
import '../../services/ops_dispatch_service.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../user_profile_screen.dart';
import 'post_card.dart';

/// Forum board (討論區) — boards only; the following feed lives in 時間軸.
class ForumBoardView extends StatelessWidget {
  const ForumBoardView({
    super.key,
    required this.compact,
    required this.db,
    required this.did,
    required this.loading,
    required this.posts,
    required this.boards,
    required this.selectedBoardId,
    required this.hasSelectedBoard,
    required this.atProtoClient,
    required this.opsDispatchService,
    required this.onFlushPendingOps,
    required this.onCreateThread,
    required this.onCreateBoard,
    required this.onManageBoards,
    required this.onDiscoverBoards,
    required this.onOpenBoard,
  });

  final bool compact;
  final AppDatabase db;
  final String did;
  final bool loading;
  final List<PostCardData> posts;
  final List<Board> boards;
  final String? selectedBoardId;
  final bool hasSelectedBoard;
  final AtProtoClient atProtoClient;
  final OpsDispatchService opsDispatchService;
  final Future<void> Function() onFlushPendingOps;
  final Future<void> Function() onCreateThread;
  final Future<void> Function() onCreateBoard;
  final Future<void> Function() onManageBoards;

  /// Opens the network DiscoverScreen so the user can find + subscribe to
  /// boards (討論區). Surfaced both in the no-boards empty state and as an
  /// always-available action in the board-actions row / bottom bar.
  final VoidCallback onDiscoverBoards;

  /// Enters a board's own page (its thread list) by local board id. Wired to
  /// the tappable board row so users can jump into a board straight from the
  /// forum tab instead of digging through the sidebar / board sheet.
  final ValueChanged<String> onOpenBoard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styleData = ElixScreenStyleScope.dataOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subscribed boards, tappable to enter each board's thread list — so the
        // forum tab itself offers a way into boards (not just the sidebar/sheet).
        if (boards.isNotEmpty) _BoardStrip(boards: boards, onOpenBoard: onOpenBoard),
        // Compact (phone): a clear entry to manage subscribed boards. On wide
        // layouts the same action lives in the board-actions row below.
        if (compact)
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onDiscoverBoards,
                  icon: const Icon(Icons.explore_outlined, size: 18),
                  tooltip: context.uiCopy(zh: '探索', en: 'Discover'),
                  visualDensity: VisualDensity.compact,
                ),
                TextButton.icon(
                  onPressed: onManageBoards,
                  icon: const Icon(Icons.tune, size: 16),
                  label: Text(l10n.manageBoardsShort),
                ),
              ],
            ),
          ),
        if (!compact) ...[
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
                      onPressed: onDiscoverBoards,
                      icon: const Icon(Icons.explore_outlined),
                      label: _ActionLabel(
                        context.uiCopy(zh: '探索', en: 'Discover'),
                      ),
                    ),
                  ),
                  action(
                    OutlinedButton.icon(
                      onPressed: boards.isNotEmpty ? onCreateThread : null,
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
              ? (boards.isEmpty
                    ? _noBoardsEmptyState(context)
                    : Center(
                        child: Text(
                          l10n.noPostsYet,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: AnsibleDesign.inkMuted),
                        ),
                      ))
              : ListView.separated(
                  itemCount: posts.length,
                  separatorBuilder: (_, _) => const SizedBox.shrink(),
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
                  fontSize: 11,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: boards.isNotEmpty ? onCreateThread : onCreateBoard,
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

  /// Shown when the user hasn't subscribed to any board (討論區). The bare
  /// "no posts" message gave no path to board discovery; this surfaces a clear
  /// CTA into the DiscoverScreen plus the existing create-board affordance.
  Widget _noBoardsEmptyState(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.uiCopy(
                zh: '還沒有訂閱任何討論區',
                en: "You haven't followed any boards yet",
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AnsibleDesign.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.uiCopy(
                zh: '到「探索」尋找討論區追蹤，貼文就會出現在這裡。',
                en: 'Find boards to follow in Discover — their posts will '
                    'appear here.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AnsibleDesign.inkMuted,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onDiscoverBoards,
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: Text(context.uiCopy(zh: '尋找討論區', en: 'Find boards to follow')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onCreateBoard,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addBoardTooltip),
            ),
          ],
        ),
      ),
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

/// Horizontal row of the user's subscribed boards; tapping one enters its
/// thread list. Gives the forum tab a direct path into boards.
class _BoardStrip extends StatelessWidget {
  const _BoardStrip({required this.boards, required this.onOpenBoard});

  final List<Board> boards;
  final ValueChanged<String> onOpenBoard;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: boards.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final board = boards[index];
            return ActionChip(
              label: Text(
                board.title,
                style: const TextStyle(fontSize: 12.5),
              ),
              avatar: const Icon(Icons.forum_outlined, size: 15),
              onPressed: () => onOpenBoard(board.id),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          },
        ),
      ),
    );
  }
}
