import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import 'home_types.dart';

/// Collapses the compact navigation out of the layout while keeping its
/// appearance/disappearance smooth. Hidden controls are also removed from hit
/// testing and semantics so screen readers cannot focus off-screen actions.
class AutoHidingHomeBottomBar extends StatelessWidget {
  const AutoHidingHomeBottomBar({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        key: const Key('home_bottom_navigation_reveal'),
        tween: Tween<double>(end: visible ? 1 : 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, reveal, navigation) {
          return Align(
            alignment: Alignment.bottomCenter,
            heightFactor: reveal,
            child: Transform.translate(
              offset: Offset(0, (1 - reveal) * 12),
              child: Opacity(
                opacity: reveal,
                child: IgnorePointer(
                  ignoring: reveal < 0.99,
                  child: ExcludeSemantics(
                    excluding: reveal < 0.99,
                    child: navigation!,
                  ),
                ),
              ),
            ),
          );
        },
        child: child,
      ),
    );
  }
}

/// Elix Forest Letter bottom tabbar: icon-only cells — home (時間軸) ·
/// circle (討論區) · a bordered center ＋ · bell (通知) · eye (我). Active cells
/// switch to ink; inactive stay faint (no labels, no filled variants). The
/// center ＋ is a rounded-rect with a soft fill + hairline rule, not a solid
/// disc. Replaces the top board-swipe tabs on compact (phone) layouts.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    final rule = dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: rule, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _board(
                context,
                HomeBoard.timeline,
                Icons.home_outlined,
                context.uiCopy(zh: '時間軸', en: 'Timeline'),
              ),
              _board(
                context,
                HomeBoard.forum,
                Icons.radio_button_checked,
                context.uiCopy(zh: '討論區', en: 'Forum'),
              ),
              _compose(context),
              _action(
                context,
                unreadCount > 0
                    ? Icons.notifications
                    : Icons.notifications_none,
                context.uiCopy(zh: '通知', en: 'Alerts'),
                onNotifications,
                showDot: unreadCount > 0,
                active: notificationsActive,
              ),
              _action(
                context,
                Icons.visibility_outlined,
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
    String label,
  ) {
    final active = boardActive && selectedBoard == board;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          key: Key('board_switch_${board.name}'),
          onTap: () => onSelectBoard(board),
          customBorder: const StadiumBorder(),
          child: _cell(context, icon, active),
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool showDot = false,
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
          customBorder: const StadiumBorder(),
          child: _cell(context, icon, active, showDot: showDot),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    IconData icon,
    bool active, {
    bool showDot = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? (dark ? AnsibleDesign.darkInk : AnsibleDesign.ink)
        : (dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint);
    final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    return SizedBox(
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 26, color: color),
          if (showDot)
            Positioned(
              top: 6,
              left: null,
              right: 0,
              child: Container(
                margin: const EdgeInsets.only(right: 14),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: AnsibleDesign.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: background, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Center ＋ — a flat lavender rounded-rect with an Ink glyph.
  Widget _compose(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Semantics(
        button: true,
        label: context.uiCopy(zh: '發表貼文', en: 'New post'),
        child: InkWell(
          onTap: onCompose,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            key: const Key('home_bottom_compose_button'),
            width: 52,
            height: 40,
            decoration: BoxDecoration(
              color: AnsibleDesign.ochre,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.add,
              size: 23,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AnsibleDesign.darkPaper
                  : AnsibleDesign.ink,
            ),
          ),
        ),
      ),
    );
  }
}
