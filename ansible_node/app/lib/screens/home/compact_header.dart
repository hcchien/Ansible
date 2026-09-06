import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';

/// Shared, fixed header for the phone's main destinations.
class HomeCompactHeader extends StatelessWidget {
  const HomeCompactHeader({
    super.key,
    required this.colors,
    required this.onSearch,
    required this.onSync,
    required this.onNotifications,
    this.syncing = false,
    this.notificationsActive = false,
    this.unreadCount = 0,
  });

  final ElixScreenStyleData colors;
  final VoidCallback onSearch;
  final VoidCallback onSync;
  final VoidCallback? onNotifications;
  final bool syncing;
  final bool notificationsActive;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final notificationLabel = unreadCount > 0
        ? context.uiCopy(
            zh: '通知，$unreadCount 則未讀',
            en: 'Notifications, $unreadCount unread',
          )
        : context.uiCopy(zh: '通知', en: 'Notifications');
    return Material(
      key: const Key('home_compact_header'),
      color: colors.background,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AnsibleMark(size: 20, color: colors.foreground),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  AnsibleDesign.brandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
              ),
              IconButton(
                onPressed: onSearch,
                tooltip: context.uiCopy(zh: '搜尋', en: 'Search'),
                icon: Icon(Icons.search, color: colors.foreground),
              ),
              IconButton(
                key: const Key('compact_home_sync_button'),
                onPressed: syncing ? null : onSync,
                tooltip: context.uiCopy(zh: '同步', en: 'Sync'),
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.sync, color: colors.foreground),
              ),
              Semantics(
                selected: notificationsActive,
                child: IconButton(
                  key: const Key('home_notifications_button'),
                  onPressed: onNotifications,
                  tooltip: notificationLabel,
                  icon: Badge(
                    key: const Key('home_notification_badge'),
                    isLabelVisible: unreadCount > 0,
                    child: Icon(
                      unreadCount > 0 || notificationsActive
                          ? Icons.notifications
                          : Icons.notifications_none,
                      color: colors.foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
