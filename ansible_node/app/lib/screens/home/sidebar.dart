import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';

class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    super.key,
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
