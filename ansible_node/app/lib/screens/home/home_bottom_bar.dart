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

/// Main destinations with a separate center compose action.
class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({
    super.key,
    required this.selectedBoard,
    required this.onSelectBoard,
    required this.onCompose,
    required this.onNotifications,
    required this.onProfile,
    this.onDiscover,
    this.discoverActive = false,
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
  final VoidCallback? onDiscover;
  final bool discoverActive;

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
              if (onDiscover != null)
                _action(
                  context,
                  Icons.explore_outlined,
                  context.uiCopy(zh: '探索', en: 'Discover'),
                  onDiscover!,
                  cellKey: const Key('home_discover_tab'),
                  active:
                      discoverActive ||
                      (boardActive && selectedBoard == HomeBoard.forum),
                )
              else
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
          child: _cell(context, icon, active, label: label),
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
          child: _cell(context, icon, active, label: label, showDot: showDot),
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    IconData icon,
    bool active, {
    bool showDot = false,
    required String label,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? (dark ? AnsibleDesign.darkInk : AnsibleDesign.ink)
        : (dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint);
    final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    return SizedBox(
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 3),
              ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ),
            ],
          ),
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
                  color: dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss,
                  shape: BoxShape.circle,
                  border: Border.all(color: background, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Center ＋ — the lichen-green rounded rectangle from b01.
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
              color: Theme.of(context).brightness == Brightness.dark
                  ? AnsibleDesign.darkOchre
                  : AnsibleDesign.accent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.add, size: 23, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
