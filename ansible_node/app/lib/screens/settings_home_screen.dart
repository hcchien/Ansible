import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/subpage_l10n.dart';
import '../services/app_locale_controller.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'credential_admin_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';
import 'sync_settings_screen.dart';
import 'wallet_screen.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({
    super.key,
    required this.db,
    required this.did,
    this.localeController,
    this.onClearIdentity,
  });

  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final VoidCallback? onClearIdentity;

  @override
  Widget build(BuildContext context) {
    final text = _SettingsText.of(context);
    return AnsibleScreenScaffold(
      title: text.settingsTitle,
      leadingLabel: '',
      trailing: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: Text(
          text.done,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
      ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AnsibleDesign.accentSoft,
                    border: Border.all(color: AnsibleDesign.accent, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person_outline,
                    size: 24,
                    color: AnsibleDesign.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.localIdentity,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${text.localDid} · ${_shortDid(did)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 9.5,
                          letterSpacing: 1,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(did: did),
                      ),
                    );
                  },
                  child: Text(
                    text.edit,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SettingsSection(
            label: text.identityAndDevice,
            children: [
              FutureBuilder<List<WalletCredential>>(
                future: DriftWalletRepository(db).listCredentials(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return AnsibleSettingsRow(
                    glyph: '◎',
                    label: text.wallet,
                    en: 'WALLET',
                    sub: text.walletSubtitle(count),
                    value: count == 0 ? text.empty : '$count',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WalletScreen(
                            holderDid: did,
                            repository: DriftWalletRepository(db),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              AnsibleSettingsRow(
                glyph: '↔',
                label: text.sync,
                en: 'SYNC',
                sub: text.syncSubtitle,
                value: text.configured,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SyncSettingsScreen(db: db),
                    ),
                  );
                },
              ),
              AnsibleSettingsRow(
                glyph: '□',
                label: text.accessAudit,
                en: 'ADMIN',
                sub: text.accessAuditSubtitle,
                value: text.noSuspiciousAccess,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CredentialAdminScreen(),
                    ),
                  );
                },
              ),
              _LanguageSettingsRow(
                localeController: localeController,
                text: text,
                last: true,
              ),
            ],
          ),
          _SettingsSection(
            label: text.daily,
            children: [
              AnsibleSettingsRow(
                glyph: '◐',
                label: text.inbox,
                en: 'INBOX',
                sub: text.inboxSubtitle,
                value: '0',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const InboxScreen()),
                  );
                },
              ),
              AnsibleSettingsRow(
                glyph: '◇',
                label: text.notifications,
                en: 'NOTIFICATIONS',
                sub: text.notificationsSubtitle,
                value: text.light,
              ),
              AnsibleSettingsRow(
                glyph: 'A',
                label: text.readingPreferences,
                en: 'READING',
                sub: text.readingPreferencesSubtitle,
                value: text.defaultValue,
                last: true,
              ),
            ],
          ),
          _SettingsSection(
            label: text.boundaries,
            children: [
              AnsibleSettingsRow(
                glyph: '●',
                label: text.lock,
                en: 'LOCK',
                sub: text.lockSubtitle,
                value: text.off,
              ),
              AnsibleSettingsRow(
                glyph: '⌷',
                label: text.backupRestore,
                en: 'RECOVERY',
                sub: text.backupRestoreSubtitle,
                value: text.notSet,
              ),
              AnsibleSettingsRow(
                glyph: '⊘',
                label: text.blockedList,
                en: 'BLOCKED',
                sub: text.blockedListSubtitle,
                value: '0',
                last: true,
              ),
            ],
          ),
          _SettingsSection(
            label: '${text.about} · ABOUT',
            children: [
              AnsibleSettingsRow(
                glyph: 'i',
                label: text.about,
                en: 'ABOUT',
                sub: text.aboutSubtitle,
              ),
              AnsibleSettingsRow(glyph: '?', label: text.manual, en: 'MANUAL'),
              AnsibleSettingsRow(
                glyph: '!',
                label: text.signOutDevice,
                en: 'SIGN OUT',
                sub: text.signOutSubtitle,
                danger: true,
                last: true,
                onTap: () => _confirmClearIdentity(context),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 20, 22, 32),
            child: Text(
              'ANSIBLE · v0.7.2 · LOCAL-FIRST',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9.5,
                letterSpacing: 1.2,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearIdentity(BuildContext context) async {
    if (onClearIdentity == null) return;
    final text = _SettingsText.of(context);
    final subpageText = SubpageL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(subpageText.t('clearLocalIdentityTitle')),
        content: Text(subpageText.t('clearLocalIdentityMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(text.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(subpageText.t('clear')),
          ),
        ],
      ),
    );
    if (confirmed == true) onClearIdentity!();
  }

  static String _shortDid(String did) {
    if (did.length <= 20) return did;
    return '${did.substring(0, 14)}...${did.substring(did.length - 4)}';
  }
}

class _LanguageSettingsRow extends StatelessWidget {
  const _LanguageSettingsRow({
    required this.localeController,
    required this.text,
    required this.last,
  });

  final AppLocaleController? localeController;
  final _SettingsText text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final controller = localeController;
    if (controller == null) {
      return AnsibleSettingsRow(
        glyph: '文',
        label: text.language,
        en: 'LANGUAGE',
        sub: text.languageSubtitle,
        value: text.systemDefault,
        last: last,
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return AnsibleSettingsRow(
          glyph: '文',
          label: text.language,
          en: 'LANGUAGE',
          sub: text.languageSubtitle,
          value: text.localeName(controller.preference),
          last: last,
          onTap: () => _showLanguagePicker(context, controller, text),
        );
      },
    );
  }

  Future<void> _showLanguagePicker(
    BuildContext context,
    AppLocaleController controller,
    _SettingsText text,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                    child: AnsibleMonoLabel(text.languagePickerTitle),
                  ),
                  AnsibleRuleGroup(
                    children: [
                      for (
                        var i = 0;
                        i < AppLocalePreference.values.length;
                        i += 1
                      )
                        _LanguageOptionRow(
                          label: text.localeName(AppLocalePreference.values[i]),
                          sub:
                              AppLocalePreference.values[i] ==
                                  AppLocalePreference.system
                              ? text.languageSystemDescription
                              : null,
                          selected:
                              controller.preference ==
                              AppLocalePreference.values[i],
                          last: i == AppLocalePreference.values.length - 1,
                          onTap: () async {
                            await controller.setPreference(
                              AppLocalePreference.values[i],
                            );
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _LanguageOptionRow extends StatelessWidget {
  const _LanguageOptionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.last = false,
  });

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
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
                      fontSize: 14,
                      color: AnsibleDesign.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AnsibleDesign.accent),
          ],
        ),
      ),
    );
  }
}

class _SettingsText {
  const _SettingsText(this.l10n);

  final AppLocalizations? l10n;

  static _SettingsText of(BuildContext context) => _SettingsText(
    Localizations.of<AppLocalizations>(context, AppLocalizations),
  );

  String get settingsTitle => l10n?.settingsTitle ?? 'SETTINGS';
  String get done => l10n?.done ?? '完成';
  String get localIdentity => l10n?.localIdentity ?? '本機身分';
  String get localDid => l10n?.localDid ?? '本機 DID';
  String get edit => l10n?.edit ?? '編輯';
  String get identityAndDevice => l10n?.identityAndDevice ?? '身分與裝置 · IDENTITY';
  String get wallet => l10n?.wallet ?? '錢包';
  String walletSubtitle(int count) => count == 0
      ? (l10n?.walletSubtitleEmpty ?? '尚無憑證')
      : (l10n?.walletSubtitleCount(count) ?? '$count 個憑證');
  String get empty => l10n?.empty ?? '空';
  String get sync => l10n?.sync ?? '同步';
  String get syncSubtitle =>
      l10n?.syncSubtitle ?? 'Forum Host / Nostr relay 設定';
  String get configured => l10n?.configured ?? '設定';
  String get accessAudit => l10n?.accessAudit ?? '存取與審計';
  String get accessAuditSubtitle => l10n?.accessAuditSubtitle ?? '誰看見了哪一個我';
  String get noSuspiciousAccess => l10n?.noSuspiciousAccess ?? '0 可疑';
  String get language => l10n?.language ?? '語言';
  String get languageSubtitle => l10n?.languageSubtitle ?? '選擇 app 介面語言';
  String get systemDefault => l10n?.systemDefault ?? '跟隨系統';
  String get daily => l10n?.daily ?? '日常 · DAILY';
  String get inbox => l10n?.inbox ?? '收信';
  String get inboxSubtitle => l10n?.inboxSubtitle ?? '圈內回覆、新成員、同步';
  String get notifications => l10n?.notifications ?? '通知';
  String get notificationsSubtitle =>
      l10n?.notificationsSubtitle ?? '決定哪些事會打擾你';
  String get light => l10n?.light ?? '輕';
  String get readingPreferences => l10n?.readingPreferences ?? '閱讀偏好';
  String get readingPreferencesSubtitle =>
      l10n?.readingPreferencesSubtitle ?? '字級、行距、主題';
  String get defaultValue => l10n?.defaultValue ?? '預設';
  String get boundaries => l10n?.boundaries ?? '邊界 · BOUNDARIES';
  String get lock => l10n?.lock ?? '鎖定';
  String get lockSubtitle => l10n?.lockSubtitle ?? '把 app 變成空白封面';
  String get off => l10n?.off ?? '關閉';
  String get backupRestore => l10n?.backupRestore ?? '備份與還原';
  String get backupRestoreSubtitle =>
      l10n?.backupRestoreSubtitle ?? 'passphrase、新裝置遷移';
  String get notSet => l10n?.notSet ?? '未設';
  String get blockedList => l10n?.blockedList ?? '封鎖名單';
  String get blockedListSubtitle => l10n?.blockedListSubtitle ?? '你看不到，他們也看不到你';
  String get about => l10n?.about ?? '關於 Elix';
  String get aboutSubtitle => l10n?.aboutSubtitle ?? '信號越過星際的距離';
  String get manual => l10n?.manual ?? '使用手冊';
  String get signOutDevice => l10n?.signOutDevice ?? '登出此裝置';
  String get signOutSubtitle => l10n?.signOutSubtitle ?? '保留資料；下次需要 passkey';
  String get languagePickerTitle => l10n?.languagePickerTitle ?? '語言';
  String get languageSystemDescription =>
      l10n?.languageSystemDescription ?? '使用裝置的語言設定';
  String get cancel => l10n?.cancel ?? '取消';

  String localeName(AppLocalePreference preference) {
    if (preference == AppLocalePreference.system) return systemDefault;
    return preference.nativeName;
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(
          label,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        ),
        AnsibleRuleGroup(children: children),
      ],
    );
  }
}
