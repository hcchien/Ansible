import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/subpage_l10n.dart';
import '../services/app_locale_controller.dart';
import '../services/reading_preferences_controller.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'blocked_list_screen.dart';
import 'credential_admin_screen.dart';
import 'inbox_screen.dart';
import 'profile_screen.dart';
import 'reading_preferences_screen.dart';
import 'sync_settings_screen.dart';
import 'wallet_screen.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({
    super.key,
    required this.db,
    required this.did,
    this.localeController,
    this.readingPreferencesController,
    this.onClearIdentity,
    this.personalScreenStyle,
    this.forumScreenStyle,
    this.boardMotion,
    this.onPersonalScreenStyleChanged,
    this.onForumScreenStyleChanged,
    this.onBoardMotionChanged,
  });

  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;
  final VoidCallback? onClearIdentity;
  final ElixScreenStyle? personalScreenStyle;
  final ElixScreenStyle? forumScreenStyle;
  final ElixBoardMotion? boardMotion;
  final ValueChanged<ElixScreenStyle>? onPersonalScreenStyleChanged;
  final ValueChanged<ElixScreenStyle>? onForumScreenStyleChanged;
  final ValueChanged<ElixBoardMotion>? onBoardMotionChanged;

  @override
  Widget build(BuildContext context) {
    final text = _SettingsText.of(context);
    return AnsibleScreenScaffold(
      title: text.settingsTitle,
      leadingLabel: '',
      trailing: TextButton(
        key: const Key('settings_done_button'),
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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              text.localIdentity,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: AnsibleDesign.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const ElixSignedPill(kind: 'PK'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'SIGNED · PASSKEY',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 8.5,
                          letterSpacing: 1.2,
                          color: AnsibleDesign.ochre,
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
                last: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CredentialAdminScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          _SettingsSection(
            label: text.interfaceAndLanguage,
            children: [
              _InterfaceSettingsPanel(
                text: text,
                personalStyle: personalScreenStyle ?? ElixScreenStyle.ink,
                forumStyle: forumScreenStyle ?? ElixScreenStyle.paper,
                motion: boardMotion ?? ElixBoardMotion.book,
                onPersonalStyleChanged: onPersonalScreenStyleChanged,
                onForumStyleChanged: onForumScreenStyleChanged,
                onMotionChanged: onBoardMotionChanged,
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
                value: text.readingPreferenceValue(
                  readingPreferencesController?.textScale,
                ),
                last: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReadingPreferencesScreen(
                        controller: readingPreferencesController,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          _SettingsSection(
            label: text.boundaries,
            children: [
              AnsibleSettingsRow(
                glyph: '⌷',
                label: text.backupRestore,
                en: 'RECOVERY',
                sub: text.backupRestoreSubtitle,
                value: text.notSet,
                valueColor: AnsibleDesign.ember,
              ),
              _BlockedListSettingsRow(db: db, text: text, last: true),
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

class _InterfaceSettingsPanel extends StatefulWidget {
  const _InterfaceSettingsPanel({
    required this.text,
    required this.personalStyle,
    required this.forumStyle,
    required this.motion,
    this.onPersonalStyleChanged,
    this.onForumStyleChanged,
    this.onMotionChanged,
  });

  final _SettingsText text;
  final ElixScreenStyle personalStyle;
  final ElixScreenStyle forumStyle;
  final ElixBoardMotion motion;
  final ValueChanged<ElixScreenStyle>? onPersonalStyleChanged;
  final ValueChanged<ElixScreenStyle>? onForumStyleChanged;
  final ValueChanged<ElixBoardMotion>? onMotionChanged;

  @override
  State<_InterfaceSettingsPanel> createState() =>
      _InterfaceSettingsPanelState();
}

class _InterfaceSettingsPanelState extends State<_InterfaceSettingsPanel> {
  late ElixScreenStyle _personalStyle;
  late ElixScreenStyle _forumStyle;
  late ElixBoardMotion _motion;

  @override
  void initState() {
    super.initState();
    _personalStyle = widget.personalStyle;
    _forumStyle = widget.forumStyle;
    _motion = widget.motion;
  }

  @override
  void didUpdateWidget(covariant _InterfaceSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personalStyle != widget.personalStyle) {
      _personalStyle = widget.personalStyle;
    }
    if (oldWidget.forumStyle != widget.forumStyle) {
      _forumStyle = widget.forumStyle;
    }
    if (oldWidget.motion != widget.motion) {
      _motion = widget.motion;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEditStyles =
        widget.onPersonalStyleChanged != null ||
        widget.onForumStyleChanged != null;
    final canEditMotion = widget.onMotionChanged != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InterfacePanelHeading(
            title: widget.text.sceneLight,
            en: 'LIGHT',
            value: '${_personalStyle.label} / ${_forumStyle.label}',
          ),
          const SizedBox(height: 9),
          Text(
            widget.text.sceneLightSubtitle,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 12),
          _SceneStylePicker(
            keyPrefix: 'personal',
            label: widget.text.personalBoard,
            selected: _personalStyle,
            enabled: canEditStyles,
            onSelected: (style) {
              setState(() => _personalStyle = style);
              widget.onPersonalStyleChanged?.call(style);
            },
          ),
          const SizedBox(height: 10),
          _SceneStylePicker(
            keyPrefix: 'forum',
            label: widget.text.forumBoard,
            selected: _forumStyle,
            enabled: canEditStyles,
            onSelected: (style) {
              setState(() => _forumStyle = style);
              widget.onForumStyleChanged?.call(style);
            },
          ),
          const SizedBox(height: 18),
          _InterfacePanelHeading(
            title: widget.text.boardMotion,
            en: 'MOTION',
            value: _motion.label,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final motion in ElixBoardMotion.values)
                _MotionChoice(
                  key: Key('settings_motion_${motion.name}'),
                  motion: motion,
                  selected: _motion == motion,
                  enabled: canEditMotion,
                  onTap: () {
                    setState(() => _motion = motion);
                    widget.onMotionChanged?.call(motion);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InterfacePanelHeading extends StatelessWidget {
  const _InterfacePanelHeading({
    required this.title,
    required this.en,
    required this.value,
  });

  final String title;
  final String en;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14.5,
            color: AnsibleDesign.ink,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          en,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 8.5,
            letterSpacing: 1.4,
            color: AnsibleDesign.inkFaint,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 9.5,
            letterSpacing: 1.1,
            color: AnsibleDesign.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _SceneStylePicker extends StatelessWidget {
  const _SceneStylePicker({
    required this.keyPrefix,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String keyPrefix;
  final String label;
  final ElixScreenStyle selected;
  final bool enabled;
  final ValueChanged<ElixScreenStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              letterSpacing: 1.1,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              for (final style in ElixScreenStyle.values) ...[
                Expanded(
                  child: _StyleChoice(
                    key: Key(
                      'settings_style_choice_${keyPrefix}_${style.name}',
                    ),
                    style: style,
                    selected: selected == style,
                    enabled: enabled,
                    onTap: () => onSelected(style),
                  ),
                ),
                if (style != ElixScreenStyle.values.last)
                  const SizedBox(width: 7),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice({
    super.key,
    required this.style,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ElixScreenStyle style;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = style.dataFor(Theme.of(context).brightness);
    final previewColor = style == ElixScreenStyle.system
        ? AnsibleDesign.paperDeep
        : data.background;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.paperElev : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 18,
              decoration: BoxDecoration(
                color: previewColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9,
                letterSpacing: 0.8,
                color: selected ? AnsibleDesign.ink : AnsibleDesign.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotionChoice extends StatelessWidget {
  const _MotionChoice({
    super.key,
    required this.motion,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ElixBoardMotion motion;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.paperDeep : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          motion.label,
          style: TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 10,
            letterSpacing: 1.1,
            color: selected ? AnsibleDesign.ink : AnsibleDesign.inkMuted,
          ),
        ),
      ),
    );
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

class _BlockedListSettingsRow extends StatefulWidget {
  const _BlockedListSettingsRow({
    required this.db,
    required this.text,
    this.last = false,
  });

  final AppDatabase db;
  final _SettingsText text;
  final bool last;

  @override
  State<_BlockedListSettingsRow> createState() =>
      _BlockedListSettingsRowState();
}

class _BlockedListSettingsRowState extends State<_BlockedListSettingsRow> {
  late Future<int> _blockedCount;

  @override
  void initState() {
    super.initState();
    _blockedCount = _loadBlockedCount();
  }

  Future<int> _loadBlockedCount() async {
    final contacts = await DriftContactRepository(widget.db).listContacts();
    return contacts
        .where(
          (contact) =>
              contact.relationship == ContactRelationship.blocked ||
              contact.trustState == ContactTrustState.blocked ||
              contact.messengerAvailability == MessengerAvailability.blocked,
        )
        .length;
  }

  Future<void> _openBlockedList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BlockedListScreen(repository: DriftContactRepository(widget.db)),
      ),
    );
    if (!mounted) return;
    setState(() {
      _blockedCount = _loadBlockedCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _blockedCount,
      builder: (context, snapshot) {
        return AnsibleSettingsRow(
          glyph: '⊘',
          label: widget.text.blockedList,
          en: 'BLOCKED',
          sub: widget.text.blockedListSubtitle,
          value: '${snapshot.data ?? 0}',
          last: widget.last,
          onTap: _openBlockedList,
        );
      },
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
  String get wallet => l10n?.wallet ?? '皮夾';
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
  String get interfaceAndLanguage => '介面與語言';
  String get sceneLight => '每版的光';
  String get sceneLightSubtitle => '個人版與討論區可以各自使用 Paper、Ink 或 Auto。';
  String get boardMotion => '換版的動態';
  String get personalBoard => '個人版';
  String get forumBoard => '討論區';
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
  String readingPreferenceValue(ReadingTextScalePreference? preference) {
    final zh = l10n == null || l10n?.wallet == '錢包' || l10n?.wallet == '皮夾';
    return switch (preference ?? ReadingTextScalePreference.standard) {
      ReadingTextScalePreference.small => zh ? '小' : 'Small',
      ReadingTextScalePreference.standard => defaultValue,
      ReadingTextScalePreference.large => zh ? '大' : 'Large',
      ReadingTextScalePreference.extraLarge => zh ? '特大' : 'Extra large',
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
