import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/notification_preferences_controller.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// Per-category notification toggles (Phase A). Preferences gate the local
/// projector; Phase B will reuse the same categories for push opt-ins.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.controller});

  /// Injectable for tests / shared app instance; defaults to a controller
  /// over SharedPreferences.
  final NotificationPreferencesController? controller;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationPreferencesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? NotificationPreferencesController();
    if (!_controller.loaded) {
      _controller.load();
    }
  }

  String _categoryLabel(BuildContext context, NotificationCategory category) {
    return switch (category) {
      NotificationCategory.reply => context.uiCopy(zh: '回覆', en: 'Replies'),
      NotificationCategory.follow => context.uiCopy(
        zh: '新追蹤者',
        en: 'New followers',
      ),
      NotificationCategory.messenger => context.uiCopy(
        zh: '私訊',
        en: 'Messages',
      ),
    };
  }

  String _categorySubtitle(
    BuildContext context,
    NotificationCategory category,
  ) {
    return switch (category) {
      NotificationCategory.reply => context.uiCopy(
        zh: '有人回覆你的討論串或留言',
        en: 'Someone replies to your thread or post',
      ),
      NotificationCategory.follow => context.uiCopy(
        zh: '有人開始追蹤你',
        en: 'Someone starts following you',
      ),
      NotificationCategory.messenger => context.uiCopy(
        zh: '有人傳私訊給你',
        en: 'Someone sends you a message',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: 'NOTIFICATIONS',
      leadingLabel: '',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                child: Text(
                  context.uiCopy(
                    zh: '通知只存在這台裝置上，伺服器不會知道你看了什麼。',
                    en: 'Notifications live only on this device; the server '
                        'never learns what you saw.',
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ),
              AnsibleMonoLabel(
                context.uiCopy(zh: '類別 · CATEGORIES', en: 'CATEGORIES'),
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              ),
              AnsibleRuleGroup(
                children: [
                  for (final category in NotificationCategory.values)
                    _CategoryToggleRow(
                      key: Key(
                        'notification_toggle_${category.storageValue}',
                      ),
                      label: _categoryLabel(context, category),
                      subtitle: _categorySubtitle(context, category),
                      value: _controller.isEnabled(category),
                      last: category == NotificationCategory.values.last,
                      onChanged: (enabled) {
                        _controller.setEnabled(category, enabled);
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryToggleRow extends StatelessWidget {
  const _CategoryToggleRow({
    super.key,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: last
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AnsibleDesign.ink,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AnsibleDesign.ochre,
          ),
        ],
      ),
    );
  }
}
