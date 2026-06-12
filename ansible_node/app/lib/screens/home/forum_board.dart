import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../services/atproto_client.dart';
import '../../services/ops_dispatch_service.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../note_editor_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styleData = ElixScreenStyleScope.dataOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact (phone): a clear entry to manage subscribed boards. On wide
        // layouts the same action lives in the board-actions row below.
        if (compact)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onManageBoards,
              icon: const Icon(Icons.tune, size: 16),
              label: Text(l10n.manageBoardsShort),
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
                  fontSize: 11,
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
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}
