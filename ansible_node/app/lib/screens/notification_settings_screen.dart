import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_l10n.dart';
import '../services/apns_push_token_provider.dart';
import '../services/notification_preferences_controller.dart';
import '../services/push_registration_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// Per-category notification toggles (Phase A) and the content-free wake
/// push opt-in (Phase B). Category preferences gate the local projector and
/// are sent as push categories on registration.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    this.controller,
    this.db,
    this.did,
    this.pushServiceFactory,
  });

  /// Injectable for tests / shared app instance; defaults to a controller
  /// over SharedPreferences.
  final NotificationPreferencesController? controller;

  /// Needed (with [did]) for the push opt-in; the section is hidden when
  /// either is missing (e.g. legacy callers).
  final AppDatabase? db;
  final String? did;

  /// Test seam: builds the registration service for a relay base URL.
  final PushRegistrationService Function(String baseUrl)? pushServiceFactory;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const _pushEnabledKey = 'elix-push-wake-enabled';

  late final NotificationPreferencesController _controller;
  bool _pushEnabled = false;
  bool _pushBusy = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? NotificationPreferencesController();
    if (!_controller.loaded) {
      _controller.load();
    }
    _loadPushEnabled();
  }

  Future<void> _loadPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_pushEnabledKey) ?? false;
    if (mounted && enabled != _pushEnabled) {
      setState(() => _pushEnabled = enabled);
    }
  }

  bool get _pushSectionAvailable => widget.db != null && widget.did != null;

  Future<void> _setPushEnabled(bool enabled) async {
    final db = widget.db;
    final did = widget.did;
    if (db == null || did == null || _pushBusy) return;
    // Copy resolved before the async gaps (build-context lint).
    final noRelayMessage = context.uiCopy(
      zh: '請先在同步設定中加入 Relay',
      en: 'Add a relay in sync settings first',
    );
    final notConfiguredMessage = context.uiCopy(
      zh: '此版本尚未設定平台推播（FCM/APNS），暫時無法開啟',
      en: 'Platform push (FCM/APNS) is not configured in this build yet',
    );
    final failureMessage = context.uiCopy(
      zh: '推播設定失敗，請稍後再試',
      en: 'Could not update push settings; try again later',
    );
    setState(() => _pushBusy = true);
    try {
      final node = await DriftRemoteNodeRepository(db).getActive();
      if (node == null) {
        _showSnack(noRelayMessage);
        return;
      }
      final service =
          widget.pushServiceFactory?.call(node.url) ??
          PushRegistrationService(
            baseUrl: node.url,
            // Native APNS on iOS; Android stays "not configured" until the
            // FCM provider lands with the Android release work.
            tokenProvider: ApnsPushTokenProvider(),
          );
      try {
        if (enabled) {
          final categories = [
            for (final category in NotificationCategory.values)
              if (_controller.isEnabled(category)) category.storageValue,
          ];
          final registered = await service.register(
            did: did,
            categories: categories,
          );
          if (!registered) {
            // No platform push token (FCM/APNS config absent) — keep the
            // toggle off and explain instead of silently failing.
            _showSnack(notConfiguredMessage);
            return;
          }
        } else {
          await service.unregister(did: did);
        }
      } finally {
        service.close();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pushEnabledKey, enabled);
      if (mounted) setState(() => _pushEnabled = enabled);
    } catch (_) {
      _showSnack(failureMessage);
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
                    en:
                        'Notifications live only on this device; the server '
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
                      key: Key('notification_toggle_${category.storageValue}'),
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
              if (_pushSectionAvailable) ...[
                AnsibleMonoLabel(
                  context.uiCopy(zh: '推播喚醒 · PUSH', en: 'PUSH WAKE-UPS'),
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                ),
                AnsibleRuleGroup(
                  children: [
                    _CategoryToggleRow(
                      key: const Key('notification_toggle_push_wake'),
                      label: context.uiCopy(
                        zh: '背景喚醒推播',
                        en: 'Background wake pushes',
                      ),
                      subtitle: context.uiCopy(
                        zh:
                            '伺服器只會推送「去同步」的空訊號，通知內容一律在'
                            '裝置上組合，不經過 Apple/Google。',
                        en:
                            'The server only pushes an empty "go sync" '
                            'signal; notification content is composed '
                            'on-device and never passes through '
                            'Apple/Google.',
                      ),
                      value: _pushEnabled,
                      last: true,
                      onChanged: _pushBusy ? null : _setPushEnabled,
                    ),
                  ],
                ),
              ],
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

  /// Null renders the switch disabled (e.g. while a registration request
  /// is in flight).
  final ValueChanged<bool>? onChanged;
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
