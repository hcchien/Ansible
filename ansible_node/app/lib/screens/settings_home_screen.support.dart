part of 'settings_home_screen.dart';

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
  String get wallet => l10n?.wallet ?? '皮夾';
  String walletSubtitle(int count) => count == 0
      ? (l10n?.walletSubtitleEmpty ?? '尚無憑證')
      : (l10n?.walletSubtitleCount(count) ?? '$count 個憑證');
  String get empty => l10n?.empty ?? '空';
  String get sync => l10n?.sync ?? '同步';
  String get syncSubtitle => l10n?.syncSubtitle ?? 'Elix Relay 設定';
  String get configured => l10n?.configured ?? '設定';
  String get accessAudit => l10n?.accessAudit ?? '存取與審計';
  String get accessAuditSubtitle => l10n?.accessAuditSubtitle ?? '誰看見了哪一個我';
  String get noSuspiciousAccess => l10n?.noSuspiciousAccess ?? '0 可疑';
  String get language => l10n?.language ?? '語言';
  String get languageSubtitle => l10n?.languageSubtitle ?? '選擇 app 介面語言';
  String get systemDefault => l10n?.systemDefault ?? '跟隨系統';
  bool get _zh => l10n == null || l10n?.language == '語言';
  String _copy({required String zh, required String en}) => _zh ? zh : en;
  String get languageGlyph => _copy(zh: '文', en: 'A');
  String get interfaceAndLanguage =>
      _copy(zh: '介面與語言', en: 'Interface & Language');
  String get sceneLight => _copy(zh: '每版的光', en: 'Board Theme');
  String get sceneLightSubtitle => _copy(
    zh: '個人版與討論區可以各自使用 Paper、Ink 或 Auto。',
    en: 'Personal and Forum boards can each use Paper, Ink, or Auto.',
  );
  String get boardMotion => _copy(zh: '換版的動態', en: 'Board Motion');
  String get personalBoard => _copy(zh: '個人版', en: 'Personal');
  String get forumBoard => _copy(zh: '討論區', en: 'Forum');
  String get daily => l10n?.daily ?? '日常 · DAILY';
  String get inbox => l10n?.inbox ?? '收信';
  String get inboxSubtitle => l10n?.inboxSubtitle ?? '圈內回覆、新成員、同步';
  String get notifications => l10n?.notifications ?? '通知';
  String get notificationsSubtitle =>
      l10n?.notificationsSubtitle ?? '決定哪些事會打擾你';
  String get readingPreferences => l10n?.readingPreferences ?? '閱讀偏好';
  String get readingPreferencesSubtitle =>
      l10n?.readingPreferencesSubtitle ?? '字級、行距、主題';
  String readingPreferenceValue(ReadingTextScalePreference? preference) {
    return switch (preference ?? ReadingTextScalePreference.standard) {
      ReadingTextScalePreference.small => _zh ? '小' : 'Small',
      ReadingTextScalePreference.standard => defaultValue,
      ReadingTextScalePreference.large => _zh ? '大' : 'Large',
      ReadingTextScalePreference.extraLarge => _zh ? '特大' : 'Extra large',
    };
  }

  String get defaultValue => l10n?.defaultValue ?? '預設';
  String get boundaries => l10n?.boundaries ?? '邊界 · BOUNDARIES';
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
