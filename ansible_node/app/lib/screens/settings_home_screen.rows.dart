part of 'settings_home_screen.dart';

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
        glyph: text.languageGlyph,
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
          glyph: text.languageGlyph,
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

class _NotificationSettingsRow extends StatefulWidget {
  const _NotificationSettingsRow({required this.text, this.db, this.did});

  final _SettingsText text;
  final AppDatabase? db;
  final String? did;

  @override
  State<_NotificationSettingsRow> createState() =>
      _NotificationSettingsRowState();
}

class _NotificationSettingsRowState extends State<_NotificationSettingsRow> {
  static const _store = SharedPreferencesNotificationPreferencesStore();
  late Future<int> _enabledCount;

  @override
  void initState() {
    super.initState();
    _enabledCount = _loadEnabledCount();
  }

  Future<int> _loadEnabledCount() async {
    var enabled = 0;
    for (final category in NotificationCategory.values) {
      if (await _store.loadEnabled(category) ?? true) enabled += 1;
    }
    return enabled;
  }

  Future<void> _openNotificationSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NotificationSettingsScreen(db: widget.db, did: widget.did),
      ),
    );
    if (!mounted) return;
    setState(() {
      _enabledCount = _loadEnabledCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = NotificationCategory.values.length;
    return FutureBuilder<int>(
      future: _enabledCount,
      builder: (context, snapshot) {
        return AnsibleSettingsRow(
          key: const Key('settings_notifications_row'),
          glyph: '◇',
          label: widget.text.notifications,
          en: 'NOTIFICATIONS',
          sub: widget.text.notificationsSubtitle,
          value: '${snapshot.data ?? total}/$total',
          onTap: _openNotificationSettings,
        );
      },
    );
  }
}

/// Recovery-readiness indicator + entry point to the backup flow (recovery
/// design D5-b; Constitution must-have: readiness is user-visible). Shows
/// 「可復原：已備份」when a backup exists, 「⚠ 尚未備份」otherwise.
class _RecoveryReadinessRow extends StatefulWidget {
  const _RecoveryReadinessRow({
    required this.text,
    required this.did,
    required this.store,
    required this.identityPrivateKeyProvider,
  });

  final _SettingsText text;
  final String did;
  final RecoveryReadinessStore store;
  final Future<String?> Function() identityPrivateKeyProvider;

  @override
  State<_RecoveryReadinessRow> createState() => _RecoveryReadinessRowState();
}

class _RecoveryReadinessRowState extends State<_RecoveryReadinessRow> {
  late Future<bool> _hasBackup;

  @override
  void initState() {
    super.initState();
    _hasBackup = widget.store.hasBackup();
  }

  Future<void> _openBackup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IdentityBackupScreen(
          did: widget.did,
          identityPrivateKeyHex: widget.identityPrivateKeyProvider,
          readinessStore: widget.store,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _hasBackup = widget.store.hasBackup());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasBackup,
      builder: (context, snapshot) {
        final hasBackup = snapshot.data ?? false;
        return AnsibleSettingsRow(
          key: const Key('settings_recovery_row'),
          glyph: '⌷',
          label: widget.text.backupRestore,
          en: 'RECOVERY',
          sub: widget.text.backupRestoreSubtitle,
          value: hasBackup
              ? context.uiCopy(zh: '可復原：已備份', en: 'Recoverable: backed up')
              : context.uiCopy(zh: '⚠ 尚未備份', en: '⚠ No backup'),
          valueColor: hasBackup ? AnsibleDesign.spore : AnsibleDesign.ember,
          onTap: _openBackup,
        );
      },
    );
  }
}

/// Entry point to the restore-from-backup recovery wizard (recovery design
/// Task 5). Sits next to the backup/RECOVERY readiness row.
class _RecoverAccountRow extends StatelessWidget {
  const _RecoverAccountRow({
    required this.db,
    required this.did,
    required this.recoveryReadinessStore,
    this.onOpenRecoveryWizard,
  });

  final AppDatabase db;
  final String did;
  final RecoveryReadinessStore recoveryReadinessStore;
  final void Function(BuildContext context)? onOpenRecoveryWizard;

  Future<void> _installRecoveredKey(String privateKeyHex) {
    return const FlutterSecureStorage().write(
      key: 'ansible_did_private_key',
      value: privateKeyHex,
    );
  }

  void _open(BuildContext context) {
    if (onOpenRecoveryWizard != null) {
      onOpenRecoveryWizard!(context);
      return;
    }
    final service = IdentityAnchorService(
      relayClient: RelayAnchorClient(),
      anchorRepository: DriftIdentityAnchorRepository(db),
      deviceKeyStore: const SecureDeviceKeyStore(),
      readinessStore: recoveryReadinessStore,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecoveryWizardScreen(
          service: service,
          installRecoveredKey: _installRecoveredKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleSettingsRow(
      key: const Key('settings_recover_account_row'),
      glyph: '⟲',
      label: context.uiCopy(zh: '復原帳號', en: 'Recover account'),
      en: 'RESTORE',
      sub: context.uiCopy(
        zh: '用加密備份在新裝置上找回身分',
        en: 'Restore identity from an encrypted backup',
      ),
      value: context.uiCopy(zh: '從備份', en: 'From backup'),
      onTap: () => _open(context),
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

/// Per-user opt-in toggle for curated external (fediverse) content
/// (inbound-federation design D4). Default OFF; effective board visibility is
/// `board.externalInclusion AND this toggle`. The label always states it is
/// unverified external content so it is never mistaken for 真人 content.
class _ExternalContentSettingsRow extends StatefulWidget {
  const _ExternalContentSettingsRow({this.controller, this.last = false});

  final ExternalContentPreferencesController? controller;
  final bool last;

  @override
  State<_ExternalContentSettingsRow> createState() =>
      _ExternalContentSettingsRowState();
}

class _ExternalContentSettingsRowState
    extends State<_ExternalContentSettingsRow> {
  late final ExternalContentPreferencesController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? ExternalContentPreferencesController();
    if (!_controller.loaded) {
      _controller.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: widget.last
                  ? BorderSide.none
                  : const BorderSide(
                      color: AnsibleDesign.ruleSoft,
                      width: 0.5,
                    ),
            ),
          ),
          child: Row(
            children: [
              const AnsibleGlyphBox(glyph: '⊕'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          context.uiCopy(zh: '站外內容', en: 'External content'),
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 16,
                            color: AnsibleDesign.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          'FEDIVERSE',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 10,
                            letterSpacing: 1.3,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.uiCopy(
                        zh: '在開放引入的看板顯示站外（未驗證）內容；預設關閉',
                        en: 'Show unverified fediverse content on boards that '
                            'opt in; off by default',
                      ),
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Switch(
                key: const Key('settings_show_external_switch'),
                value: _controller.showExternal,
                onChanged: (enabled) =>
                    _controller.setShowExternal(enabled),
              ),
            ],
          ),
        );
      },
    );
  }
}

