import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import 'home_types.dart';

/// Threads-style bottom navigation: 時間軸 + 討論區 + a prominent central compose
/// button + 通知 + 我. Replaces the top board-swipe tab row on compact (phone)
/// layouts. 個人版 is reached from 我 (settings) instead of a dedicated cell, so
/// the ＋ sits dead-center in a symmetric five-cell bar. Only the two board cells
/// carry a persistent selected state (driven by [selectedBoard]); the ＋,
/// notifications and 我 are momentary actions.
class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({
    super.key,
    required this.selectedBoard,
    required this.onSelectBoard,
    required this.onCompose,
    required this.onNotifications,
    required this.onProfile,
    this.boardActive = true,
    this.notificationsActive = false,
    this.meActive = false,
    this.unreadCount = 0,
  });

  final HomeBoard selectedBoard;
  final ValueChanged<HomeBoard> onSelectBoard;
  final VoidCallback onCompose;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  /// Which destination is active. When a board is active, the matching board
  /// cell highlights; otherwise 通知 or 我 highlights.
  final bool boardActive;
  final bool notificationsActive;
  final bool meActive;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border(top: BorderSide(color: AnsibleDesign.rule, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _board(
                context,
                HomeBoard.timeline,
                Icons.dynamic_feed_outlined,
                Icons.dynamic_feed,
                context.uiCopy(zh: '時間軸', en: 'Timeline'),
              ),
              _board(
                context,
                HomeBoard.forum,
                Icons.forum_outlined,
                Icons.forum,
                context.uiCopy(zh: '討論區', en: 'Forum'),
              ),
              _compose(context),
              _action(
                context,
                notificationsActive
                    ? Icons.notifications
                    : Icons.notifications_outlined,
                context.uiCopy(zh: '通知', en: 'Alerts'),
                onNotifications,
                badgeCount: unreadCount,
                active: notificationsActive,
              ),
              _action(
                context,
                meActive ? Icons.person : Icons.person_outline,
                context.uiCopy(zh: '我', en: 'Me'),
                onProfile,
                cellKey: const Key('settings_button'),
                active: meActive,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _board(
    BuildContext context,
    HomeBoard board,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final active = boardActive && selectedBoard == board;
    final color = active ? AnsibleDesign.ink : AnsibleDesign.inkFaint;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          key: Key('board_switch_${board.name}'),
          onTap: () => onSelectBoard(board),
          child: _cell(active ? activeIcon : icon, label, color, active),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    int badgeCount = 0,
    Key? cellKey,
    bool active = false,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          key: cellKey,
          onTap: onTap,
          child: _cell(
            icon,
            label,
            active ? AnsibleDesign.ink : AnsibleDesign.inkFaint,
            active,
            badgeCount: badgeCount,
          ),
        ),
      ),
    );
  }

  Widget _cell(
    IconData icon,
    String label,
    Color color,
    bool active, {
    int badgeCount = 0,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: 24,
          width: 28,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 23, color: color),
              if (badgeCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                    decoration: const BoxDecoration(
                      color: AnsibleDesign.danger,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: AnsibleDesign.paper,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            height: 1,
            color: color,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _compose(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: context.uiCopy(zh: '發表貼文', en: 'New post'),
        child: InkWell(
          onTap: onCompose,
          customBorder: const CircleBorder(),
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AnsibleDesign.ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 24, color: AnsibleDesign.paper),
            ),
          ),
        ),
      ),
    );
  }
}
