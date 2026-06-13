import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/feed_filter_tabs.dart';
import 'board_swipe.dart';
import 'home_types.dart';

/// Centered swipe header with animated ochre underline.
class BoardSwipeHeader extends StatelessWidget {
  const BoardSwipeHeader({
    super.key,
    required this.pageController,
    required this.selectedBoard,
    required this.onTapBoard,
    required this.personalStyle,
    required this.timelineStyle,
    required this.forumStyle,
    required this.personalFilter,
    required this.onPersonalFilterChanged,
    required this.feedFilter,
    required this.onFeedFilterChanged,
    required this.forumPostCount,
    this.onOpenPreferences,
    this.onOpenSettings,
    this.onOpenNotifications,
    this.notificationUnreadCount = 0,
  });

  final PageController pageController;
  final HomeBoard selectedBoard;
  final ValueChanged<HomeBoard> onTapBoard;
  final ElixScreenStyle personalStyle;
  final ElixScreenStyle timelineStyle;
  final ElixScreenStyle forumStyle;
  final PersonalFilter personalFilter;
  final ValueChanged<PersonalFilter> onPersonalFilterChanged;
  final FeedFilter feedFilter;
  final ValueChanged<FeedFilter> onFeedFilterChanged;
  final int forumPostCount;
  final VoidCallback? onOpenPreferences;
  final VoidCallback? onOpenSettings;

  /// Opens the notification feed; when set, a bell icon (with the unread
  /// count from the local notifications table) joins the icon cluster.
  final VoidCallback? onOpenNotifications;
  final int notificationUnreadCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;
    final datas = [
      personalStyle.dataFor(brightness),
      timelineStyle.dataFor(brightness),
      forumStyle.dataFor(brightness),
    ];
    final maxIndex = datas.length - 1;

    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        // Smoothly interpolate header chrome between the two adjacent boards as
        // the pager scrolls (generalizes the old 2-board lerp to N boards).
        final page = boardPageValue(
          pageController,
          selectedBoard.index.toDouble(),
        ).clamp(0.0, maxIndex.toDouble()).toDouble();
        final lo = page.floor().clamp(0, maxIndex);
        final hi = page.ceil().clamp(0, maxIndex);
        final t = page - lo;
        final activeIndex = page.round().clamp(0, maxIndex);
        Color lf(Color a, Color b) => Color.lerp(a, b, t)!;
        final bgColor = lf(datas[lo].background, datas[hi].background);
        final ruleColor = lf(datas[lo].rule, datas[hi].rule);
        final fgColor = lf(datas[lo].foreground, datas[hi].foreground);
        final faintColor = lf(datas[lo].faint, datas[hi].faint);
        final mutedColor = lf(datas[lo].muted, datas[hi].muted);
        final surfaceColor = lf(datas[lo].surface, datas[hi].surface);
        final ochreColor = lf(datas[lo].accent, datas[hi].accent);

        return Container(
          color: bgColor,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(
                builder: (context) {
                  Widget btn(
                    HomeBoard board,
                    String label,
                    String tooltip, {
                    bool showMark = false,
                  }) {
                    final dist = (page - board.index).abs().clamp(0.0, 1.0);
                    return _boardButton(
                      board: board,
                      label: label,
                      tooltip: tooltip,
                      active: activeIndex == board.index,
                      showMark: showMark && activeIndex == board.index,
                      underlineOpacity: 1 - dist,
                      textColor: Color.lerp(fgColor, faintColor, dist)!,
                      ochreColor: ochreColor,
                    );
                  }

                  // Right-side icon buttons (settings, optional preferences).
                  final iconButtons = <Widget>[
                    if (onOpenNotifications != null)
                      _NotificationBell(
                        unreadCount: notificationUnreadCount,
                        color: faintColor,
                        onPressed: onOpenNotifications!,
                      ),
                    if (onOpenPreferences != null)
                      IconButton(
                        key: const Key('screen_style_button'),
                        onPressed: onOpenPreferences,
                        icon: const Icon(Icons.palette_outlined, size: 23),
                        color: faintColor,
                        tooltip: context.uiCopy(
                          zh: '介面與動態',
                          en: 'Interface and motion',
                        ),
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    if (onOpenSettings != null)
                      IconButton(
                        key: const Key('settings_button'),
                        onPressed: onOpenSettings,
                        icon: const Icon(Icons.person_outline, size: 24),
                        color: faintColor,
                        tooltip: l10n.settingsNav,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                  ];
                  // Equal side widths keep the board tabs visually centered while
                  // the icons sit at the far right (normal flow → always tappable).
                  // 48 = Material minimum tap target per icon.
                  final sideWidth = iconButtons.length * 48.0;

                  return Row(
                    children: [
                      SizedBox(width: sideWidth),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                btn(
                                  HomeBoard.personal,
                                  context.uiCopy(zh: '個人版', en: 'Personal'),
                                  context.uiCopy(
                                    zh: '個人版 · 你的 Note 和 Murmur',
                                    en: 'Personal · your Notes and Murmurs',
                                  ),
                                  showMark: true,
                                ),
                                const SizedBox(width: 24),
                                btn(
                                  HomeBoard.timeline,
                                  context.uiCopy(zh: '時間軸', en: 'Timeline'),
                                  context.uiCopy(
                                    zh: '時間軸 · 你追蹤的人的貼文',
                                    en: 'Timeline · posts from people you follow',
                                  ),
                                ),
                                const SizedBox(width: 24),
                                btn(
                                  HomeBoard.forum,
                                  context.uiCopy(zh: '討論區', en: 'Forum'),
                                  context.uiCopy(
                                    zh: '討論區 · 看板',
                                    en: 'Forum · boards',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: sideWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: iconButtons,
                        ),
                      ),
                    ],
                  );
                },
              ),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: ruleColor, width: 0.5)),
                ),
                child: activeIndex == HomeBoard.personal.index
                    ? _personalMetaRow(
                        context: context,
                        fgColor: fgColor,
                        mutedColor: mutedColor,
                        faintColor: faintColor,
                        surfaceColor: surfaceColor,
                        ruleColor: ruleColor,
                        ochreColor: ochreColor,
                      )
                    : activeIndex == HomeBoard.timeline.index
                    ? _timelineMetaRow(context: context, faintColor: faintColor)
                    : _forumMetaRow(
                        context: context,
                        fgColor: fgColor,
                        mutedColor: mutedColor,
                        faintColor: faintColor,
                        surfaceColor: surfaceColor,
                        ruleColor: ruleColor,
                        ochreColor: ochreColor,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _boardButton({
    required HomeBoard board,
    required String label,
    required String tooltip,
    required bool active,
    required bool showMark,
    required double underlineOpacity,
    required Color textColor,
    required Color ochreColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: active,
        label: tooltip,
        child: InkWell(
          key: Key('board_switch_${board.name}'),
          onTap: () => onTapBoard(board),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showMark) ...[
                      AnsibleMark(size: 13, color: textColor),
                      const SizedBox(width: 7),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                        color: textColor,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: underlineOpacity,
                  child: Container(
                    width: 24,
                    height: 2,
                    decoration: BoxDecoration(
                      color: ochreColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timelineMetaRow({
    required BuildContext context,
    required Color faintColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            context.uiCopy(
              zh: '你追蹤的人的最新貼文',
              en: 'Latest from people you follow',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Prose (often CJK) — use the default font, not the mono label face
            // (JetBrains Mono lacks CJK glyphs and renders an odd fallback).
            style: TextStyle(fontSize: 13, height: 1.3, color: faintColor),
          ),
        ),
      ],
    );
  }

  Widget _personalMetaRow({
    required BuildContext context,
    required Color fgColor,
    required Color mutedColor,
    required Color faintColor,
    required Color surfaceColor,
    required Color ruleColor,
    required Color ochreColor,
  }) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: Text(
            _todayLabel(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.3, color: faintColor),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FocusHeaderChip(
                label: l10n.searchScopeAll,
                selected: personalFilter == PersonalFilter.all,
                onTap: () => onPersonalFilterChanged(PersonalFilter.all),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
              _FocusHeaderChip(
                label: 'murmur',
                selected: personalFilter == PersonalFilter.murmur,
                onTap: () => onPersonalFilterChanged(PersonalFilter.murmur),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
              _FocusHeaderChip(
                label: 'note',
                selected: personalFilter == PersonalFilter.note,
                onTap: () => onPersonalFilterChanged(PersonalFilter.note),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _forumMetaRow({
    required BuildContext context,
    required Color fgColor,
    required Color mutedColor,
    required Color faintColor,
    required Color surfaceColor,
    required Color ruleColor,
    required Color ochreColor,
  }) {
    final l10n = context.l10n;
    final activeFilter = feedFilter == FeedFilter.boards
        ? FeedFilter.boards
        : FeedFilter.following;
    return Row(
      children: [
        Expanded(
          child: Text(
            context.uiCopy(
              zh: '$forumPostCount 新 · 今',
              en: '$forumPostCount new · today',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, height: 1.3, color: faintColor),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FocusHeaderChip(
                label: l10n.feedFollowing,
                selected: activeFilter == FeedFilter.following,
                onTap: () => onFeedFilterChanged(FeedFilter.following),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
              _FocusHeaderChip(
                label: l10n.feedBoards,
                selected: activeFilter == FeedFilter.boards,
                onTap: () => onFeedFilterChanged(FeedFilter.boards),
                fgColor: fgColor,
                mutedColor: mutedColor,
                surfaceColor: surfaceColor,
                ruleColor: ruleColor,
                ochreColor: ochreColor,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final weekday = weekdays[now.weekday - 1];
    return '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} $weekday';
  }
}

/// Bell icon with the local unread-notification count. Badge truth is local:
/// the count comes from the device's notifications table, never a server.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.unreadCount,
    required this.color,
    required this.onPressed,
  });

  final int unreadCount;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          key: const Key('notifications_button'),
          onPressed: onPressed,
          icon: const Icon(Icons.notifications_none, size: 23),
          color: color,
          tooltip: context.uiCopy(zh: '通知', en: 'Notifications'),
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
        ),
        if (unreadCount > 0)
          Positioned(
            top: 6,
            right: 4,
            child: IgnorePointer(
              child: Container(
                key: const Key('notifications_unread_badge'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4.5,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: AnsibleDesign.ochre,
                  borderRadius: BorderRadius.circular(999),
                ),
                constraints: const BoxConstraints(minWidth: 15),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 8.5,
                    height: 1.2,
                    letterSpacing: 0.2,
                    color: AnsibleDesign.paper,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FocusHeaderChip extends StatelessWidget {
  const _FocusHeaderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.fgColor,
    required this.mutedColor,
    required this.surfaceColor,
    required this.ruleColor,
    required this.ochreColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color fgColor;
  final Color mutedColor;
  final Color surfaceColor;
  final Color ruleColor;
  final Color ochreColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? surfaceColor : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? ruleColor : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: selected ? fgColor : mutedColor,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
