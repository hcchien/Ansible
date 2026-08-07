part of 'settings_home_screen.dart';

class _IssuerToolsFold extends StatefulWidget {
  const _IssuerToolsFold({required this.did, required this.capabilities});

  final String did;
  final PlatformCapabilities capabilities;

  @override
  State<_IssuerToolsFold> createState() => _IssuerToolsFoldState();
}

class _IssuerToolsFoldState extends State<_IssuerToolsFold> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnsibleSettingsRow(
          key: const Key('settings_issuer_tools_fold'),
          glyph: '◇',
          label: context.uiCopy(zh: '簽發憑證與組織工具', en: 'Credential issuer tools'),
          en: 'ADVANCED',
          sub: context.uiCopy(
            zh: widget.capabilities.hardwareIdentityKey
                ? '需要自行簽發會員憑證時再設定'
                : '需要不可匯出的硬體金鑰；此裝置為降低信任模式',
            en: widget.capabilities.hardwareIdentityKey
                ? 'Set up only if you need to issue membership credentials'
                : 'Requires a non-exportable hardware key; this device is reduced trust',
          ),
          value: _expanded
              ? context.uiCopy(zh: '收合', en: 'Hide')
              : context.uiCopy(zh: '展開', en: 'Show'),
          trailingIcon: _expanded ? Icons.expand_less : Icons.expand_more,
          onTap: widget.capabilities.hardwareIdentityKey
              ? () => setState(() => _expanded = !_expanded)
              : null,
        ),
        if (_expanded) ...[
          AnsibleSettingsRow(
            key: const Key('settings_hosted_issuer_row'),
            glyph: '◇',
            label: context.uiCopy(zh: '代管簽發者', en: 'Hosted Issuer'),
            en: 'ISSUER',
            sub: context.uiCopy(
              zh: '組織會員憑證與簽章治理',
              en: 'Organization credentials and signing governance',
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      HostedIssuerOnboardingScreen(ownerDid: widget.did),
                ),
              );
            },
          ),
          AnsibleSettingsRow(
            key: const Key('settings_hosted_issuer_admins_row'),
            glyph: '⋮',
            label: context.uiCopy(zh: '簽發者管理員', en: 'Issuer administrators'),
            en: 'GOVERNANCE',
            sub: context.uiCopy(
              zh: '加入請求、Passkey 與多人核准',
              en: 'Enrollment, passkeys, and multi-admin approval',
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      HostedIssuerAdministratorsScreen(localDid: widget.did),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _IdentityCustodyRow extends StatefulWidget {
  const _IdentityCustodyRow({required this.did, required this.capabilities});
  final String did;
  final PlatformCapabilities capabilities;

  @override
  State<_IdentityCustodyRow> createState() => _IdentityCustodyRowState();
}

class _IdentityCustodyRowState extends State<_IdentityCustodyRow> {
  late Future<CanonicalIdentity?> _identity;
  bool _upgrading = false;

  @override
  void initState() {
    super.initState();
    _identity = const SecureCanonicalIdentityStore().load();
  }

  Future<void> _upgrade() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.uiCopy(zh: '升級身分金鑰', en: 'Upgrade identity key')),
        content: Text(
          context.uiCopy(
            zh: '新私鑰會留在裝置安全硬體中且無法匯出。Elix 會用舊、新金鑰共同簽署 rotation；伺服器確認前不會切換。',
            en: 'The new private key stays non-exportable in device hardware. Elix dual-signs the rotation and switches only after relay confirmation.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.uiCopy(zh: '升級', en: 'Upgrade')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _upgrading = true);
    try {
      await HardwareKeyUpgradeService().upgrade();
      if (!mounted) return;
      setState(() {
        _identity = const SecureCanonicalIdentityStore().load();
        _upgrading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(zh: '硬體金鑰升級完成', en: 'Hardware key upgrade complete'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _upgrading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CanonicalIdentity?>(
      future: _identity,
      builder: (context, snapshot) {
        final hardware = snapshot.data?.custody == 'hardware';
        final value = hardware
            ? context.uiCopy(zh: '硬體保護', en: 'Hardware-backed')
            : widget.capabilities.hardwareIdentityKey
            ? context.uiCopy(zh: '可升級', en: 'Upgrade available')
            : context.uiCopy(zh: '降低信任', en: 'Reduced trust');
        return AnsibleSettingsRow(
          key: const Key('settings_identity_custody_row'),
          glyph: '◇',
          label: context.uiCopy(zh: '身分金鑰保管', en: 'Identity key custody'),
          en: 'KEY CUSTODY',
          sub: hardware
              ? context.uiCopy(
                  zh: '私鑰不可匯出；簽章需要裝置授權',
                  en: 'Non-exportable; signing requires device authorization',
                )
              : widget.capabilities.hardwareIdentityKey
              ? context.uiCopy(
                  zh: '將舊軟體金鑰安全輪替至裝置硬體',
                  en: 'Safely rotate the legacy software key into device hardware',
                )
              : context.uiCopy(
                  zh: 'Desktop 私鑰可匯出，不可管理高敏感 Issuer',
                  en: 'Desktop keys are exportable and cannot administer sensitive issuers',
                ),
          value: _upgrading
              ? context.uiCopy(zh: '升級中…', en: 'Upgrading…')
              : value,
          valueColor: hardware ? AnsibleDesign.spore : AnsibleDesign.ochre,
          onTap:
              !hardware &&
                  widget.capabilities.hardwareIdentityKey &&
                  !_upgrading
              ? _upgrade
              : null,
        );
      },
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
        key: const Key('settings_language_row'),
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
          key: const Key('settings_language_row'),
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
  const _NotificationSettingsRow({
    required this.text,
    required this.capabilities,
    this.db,
    this.did,
  });

  final _SettingsText text;
  final AppDatabase? db;
  final String? did;
  final PlatformCapabilities capabilities;

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
        builder: (_) => NotificationSettingsScreen(
          db: widget.db,
          did: widget.did,
          platformCapabilities: widget.capabilities,
        ),
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

class _FediversePublishingSettingsRow extends StatefulWidget {
  const _FediversePublishingSettingsRow({
    required this.db,
    required this.did,
    this.controller,
  });

  final AppDatabase db;
  final String did;
  final FediversePreferencesController? controller;

  @override
  State<_FediversePublishingSettingsRow> createState() =>
      _FediversePublishingSettingsRowState();
}

class _FediversePublishingSettingsRowState
    extends State<_FediversePublishingSettingsRow> {
  late final FediversePreferencesController _controller;
  late final DidSigner _fediverseDidSigner;

  @override
  void initState() {
    super.initState();
    _fediverseDidSigner = DidSignerImpl(reuseAuthenticationContext: true);
    _controller =
        widget.controller ??
        FediversePreferencesController(
          did: widget.did,
          remoteNodes: DriftRemoteNodeRepository(widget.db),
          signer: _fediverseDidSigner,
          verifiedHumanPresenter: (node) async {
            final result = await RelayReputationPresentationService(
              walletRepository: DriftWalletRepository(widget.db),
              reputationRepository: DriftDidReputationRepository(widget.db),
              didSigner: _fediverseDidSigner,
            ).present(holderDid: widget.did, node: node);
            if (!result.presented) {
              throw StateError('activity_pub_requires_verified_human');
            }
          },
        );
    if (!_controller.loaded) _controller.load();
  }

  Future<void> _setEnabled(bool enabled) async {
    try {
      await _withHardwareAuthenticationSession(
        () => _controller.setEnabled(enabled),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  Future<T> _withHardwareAuthenticationSession<T>(
    Future<T> Function() action,
  ) async {
    // Injected controllers are a test seam and own their authorization model.
    if (widget.controller != null) return action();
    final reason = context.uiCopy(
      zh: '請驗證裝置持有人，以更新 Fediverse 設定。',
      en: 'Authenticate to update Fediverse settings.',
    );
    final session = await HardwareAuthenticationSession.begin(
      localizedReason: reason,
    );
    if (session == null) {
      final authenticated = await LocalDeviceUserPresenceVerifier().verify(
        reason: reason,
      );
      if (!authenticated) {
        throw StateError('device_auth_cancelled');
      }
    }
    try {
      return await action();
    } finally {
      await session?.close();
    }
  }

  String _message(Object error) {
    final value = error.toString().replaceFirst('Bad state: ', '');
    if (value == 'device_auth_cancelled') {
      return context.uiCopy(
        zh: '未完成裝置驗證，Fediverse 設定未變更。',
        en: 'Device authentication was not completed. Fediverse settings were unchanged.',
      );
    }
    if (value == 'activity_pub_requires_verified_human') {
      return context.uiCopy(
        zh: '需要先通過真人驗證，才能開啟 Fediverse 發布。',
        en: 'Verified-human status is required to enable Fediverse publishing.',
      );
    }
    return value;
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'[,\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> _editPolicy() async {
    var policy = _controller.preferences.domainPolicy;
    var followers = _controller.preferences.allowRemoteFollowers;
    final allowed = TextEditingController(
      text: _controller.preferences.allowedDomains.join('\n'),
    );
    final blocked = TextEditingController(
      text: _controller.preferences.blockedDomains.join('\n'),
    );
    final actors = TextEditingController(
      text: _controller.preferences.blockedActors.join('\n'),
    );
    final result = await showDialog<FediversePreferences>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            context.uiCopy(zh: 'Fediverse 站台政策', en: 'Fediverse site policy'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<FediverseDomainPolicy>(
                  initialValue: policy,
                  decoration: InputDecoration(
                    labelText: context.uiCopy(zh: '允許模式', en: 'Site policy'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: FediverseDomainPolicy.open,
                      child: Text(
                        context.uiCopy(
                          zh: '開放（封鎖清單除外）',
                          en: 'Open, except blocked',
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: FediverseDomainPolicy.allowlist,
                      child: Text(
                        context.uiCopy(zh: '僅允許清單', en: 'Allowlist only'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => policy = value);
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    context.uiCopy(
                      zh: '允許站外使用者追蹤',
                      en: 'Allow remote followers',
                    ),
                  ),
                  value: followers,
                  onChanged: (value) => setDialogState(() => followers = value),
                ),
                TextField(
                  controller: allowed,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '允許的網域（每行一個）',
                      en: 'Allowed domains (one per line)',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AnsibleDesign.danger,
                  ),
                  onPressed: !_controller.preferences.enabled
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                context.uiCopy(
                                  zh: '刪除 Fediverse 帳號？',
                                  en: 'Delete Fediverse account?',
                                ),
                              ),
                              content: Text(
                                context.uiCopy(
                                  zh:
                                      'Relay 會停止公開此帳號，並嘗試通知既有追蹤站台。'
                                      '無法保證其他站台會立即刪除已收到的副本。',
                                  en:
                                      'The Relay will hide this actor and attempt to '
                                      'notify existing followers. Remote copies '
                                      'cannot be guaranteed to disappear.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(
                                    context.uiCopy(zh: '取消', en: 'Cancel'),
                                  ),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    context.uiCopy(zh: '確認刪除', en: 'Delete'),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true || !context.mounted) return;
                          Navigator.pop(context, const FediversePreferences());
                        },
                  label: Text(
                    context.uiCopy(
                      zh: '刪除 Fediverse 帳號',
                      en: 'Delete Fediverse account',
                    ),
                  ),
                ),
                TextField(
                  controller: blocked,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '封鎖的網域（每行一個）',
                      en: 'Blocked domains (one per line)',
                    ),
                  ),
                ),
                TextField(
                  controller: actors,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '封鎖的使用者網址',
                      en: 'Blocked actor URLs',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _controller.preferences.copyWith(
                  domainPolicy: policy,
                  allowRemoteFollowers: followers,
                  allowedDomains: _lines(allowed.text),
                  blockedDomains: _lines(blocked.text),
                  blockedActors: _lines(actors.text),
                ),
              ),
              child: Text(context.uiCopy(zh: '儲存', en: 'Save')),
            ),
          ],
        ),
      ),
    );
    allowed.dispose();
    blocked.dispose();
    actors.dispose();
    if (result == null) return;
    if (!result.enabled &&
        _controller.preferences.enabled &&
        result.revision == 0) {
      try {
        final count = await _withHardwareAuthenticationSession(
          _controller.deleteFederatedAccount,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.uiCopy(
                zh: '已停用帳號，並排入 $count 個遠端刪除通知。',
                en: 'Account disabled; $count remote Delete deliveries queued.',
              ),
            ),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
      return;
    }
    try {
      await _withHardwareAuthenticationSession(
        () => _controller.update(result),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final enabled = _controller.preferences.enabled;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              const AnsibleGlyphBox(glyph: '↗'),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _controller.saving ? null : _editPolicy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.uiCopy(
                          zh: '發布到 Fediverse',
                          en: 'Publish to Fediverse',
                        ),
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                      Text(
                        context.uiCopy(
                          zh: '僅限真人驗證；點此設定允許與封鎖站台',
                          en:
                              'Verified humans only; tap to configure allowed '
                              'and blocked sites',
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
              ),
              const SizedBox(width: 8),
              Semantics(
                label: context.uiCopy(
                  zh: enabled ? 'Fediverse 發布已啟用' : 'Fediverse 發布已關閉',
                  en: enabled
                      ? 'Fediverse publishing is enabled'
                      : 'Fediverse publishing is off',
                ),
                child: Text(
                  enabled
                      ? context.uiCopy(zh: '已啟用', en: 'ON')
                      : context.uiCopy(zh: '關閉', en: 'OFF'),
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: enabled
                        ? AnsibleDesign.moss
                        : AnsibleDesign.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Switch(
                value: enabled,
                onChanged: !_controller.loaded || _controller.saving
                    ? null
                    : _setEnabled,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExternalContentSettingsRowState
    extends State<_ExternalContentSettingsRow> {
  late final ExternalContentPreferencesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ExternalContentPreferencesController();
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
                  : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
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
                        en:
                            'Show unverified fediverse content on boards that '
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
                onChanged: (enabled) => _controller.setShowExternal(enabled),
              ),
            ],
          ),
        );
      },
    );
  }
}
