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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final faint = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final accent = dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent;
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(right: BorderSide(color: rule, width: 0.5)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.circleSection,
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: faint,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add),
                color: accent,
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
              foregroundColor: foreground,
              side: BorderSide(color: rule, width: 0.5),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selected = widget.selected;
    final item = widget.item;
    final base = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    final raised = dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
    final deep = dark ? AnsibleDesign.darkPaperDeep : AnsibleDesign.paperDeep;
    final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final ruleSoft = dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
    final accent = dark ? AnsibleDesign.darkOchre : item.accent;
    final baseBg = selected ? raised : base;
    final hoverBg = selected ? deep : raised;
    final borderColor = selected
        ? accent.withValues(alpha: 0.5)
        : (_hover ? rule : ruleSoft);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hover ? hoverBg : baseBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.16),
              foregroundColor: accent,
              child: const Text(
                '#',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            title: Text(
              item.title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _hover ? accent : foreground,
              ),
            ),
            subtitle: item.subtitle != null
                ? Text(
                    item.subtitle!,
                    style: TextStyle(color: muted, fontSize: 12),
                  )
                : null,
            trailing: item.badge != null
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: deep,
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
