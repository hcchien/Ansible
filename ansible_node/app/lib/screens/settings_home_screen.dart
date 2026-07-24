import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../l10n/app_localizations.dart';
import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/app_locale_controller.dart';
import '../services/external_content_preferences_controller.dart';
import '../services/identity_anchor_service.dart';
import '../services/hardware_key_upgrade_service.dart';
import '../services/canonical_identity_store.dart';
import '../services/reading_preferences_controller.dart';
import '../services/recovery_readiness_store.dart';
import '../services/relay_anchor_client.dart';
import '../services/secure_device_key_store.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../services/notification_preferences_controller.dart';
import '../services/platform_capabilities.dart';
import 'about_screen.dart';
import 'blocked_list_screen.dart';
import 'credential_admin_screen.dart';
import 'identity_backup_screen.dart';
import 'identity_security_screen.dart';
import 'hosted_issuer_onboarding_screen.dart';
import 'hosted_issuer_administrators_screen.dart';
import 'inbox_screen.dart';
import 'local_ai_access_screen.dart';
import 'recovery_wizard_screen.dart';
import 'notification_settings_screen.dart';
import 'edit_profile_screen.dart';
import 'reading_preferences_screen.dart';
import 'sync_settings_screen.dart';
import 'wallet_screen.dart';

part 'settings_home_screen.panels.dart';
part 'settings_home_screen.rows.dart';
part 'settings_home_screen.support.dart';

/// Reads the raw Ed25519 identity private key from platform secure storage
/// (the same key [DidSignerImpl] uses). Returns null when no key is anchored.
///
/// TODO(Task 2/3): centralize this read in ansible_did so the backup screen and
/// signer share one accessor.
Future<String?> _defaultIdentityPrivateKey() {
  return const FlutterSecureStorage().read(key: 'ansible_did_private_key');
}

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({
    super.key,
    required this.db,
    required this.did,
    this.localeController,
    this.readingPreferencesController,
    this.externalContentPreferencesController,
    this.onClearIdentity,
    this.personalScreenStyle,
    this.forumScreenStyle,
    this.boardMotion,
    this.onPersonalScreenStyleChanged,
    this.onForumScreenStyleChanged,
    this.onBoardMotionChanged,
    this.recoveryReadinessStore =
        const SharedPreferencesRecoveryReadinessStore(),
    this.identityPrivateKeyProvider = _defaultIdentityPrivateKey,
    this.onOpenRecoveryWizard,
    this.onOpenPersonalBoard,
    this.embedded = false,
    this.showLocalAiAccess,
    this.platformCapabilities,
  });

  /// When true the screen is the bottom-nav 我 tab (not a pushed route), so it
  /// drops the "Done" close button — the nav switches destinations.
  final bool embedded;

  /// Local AI Access (MCP) is desktop-only by design — mobile has no local
  /// MCP clients and background execution limits. Null = decide by platform;
  /// overridable for tests.
  final bool? showLocalAiAccess;
  final PlatformCapabilities? platformCapabilities;

  PlatformCapabilities get _capabilities =>
      platformCapabilities ?? PlatformCapabilities.current;

  bool get _showLocalAiAccess =>
      showLocalAiAccess ??
      _capabilities.localAiAccess;

  /// Jumps to the user's 個人版 (personal board) in the home pager. Surfaced as
  /// the top entry here because the personal board no longer has its own cell in
  /// the bottom navigation. When null the entry is hidden.
  final VoidCallback? onOpenPersonalBoard;

  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;

  /// Per-user opt-in for curated external (fediverse) content. When null the
  /// row builds its own controller from the production SharedPreferences store.
  final ExternalContentPreferencesController?
  externalContentPreferencesController;

  /// Source of recovery-readiness state for the RECOVERY settings row.
  final RecoveryReadinessStore recoveryReadinessStore;

  /// Provides the identity private key (hex) for the backup screen. Injectable
  /// for tests; defaults to reading platform secure storage.
  final Future<String?> Function() identityPrivateKeyProvider;

  /// Opens the recovery wizard (restore-from-backup). Injectable for tests;
  /// when null the row builds a default [RecoveryWizardScreen] from production
  /// dependencies.
  final void Function(BuildContext context)? onOpenRecoveryWizard;
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
      trailing: embedded
          ? null
          : TextButton(
              key: const Key('settings_done_button'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                text.done,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  fontSize: 14,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
            ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AnsibleDesign.accent,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.person_outline,
                    size: 30,
                    color: AnsibleDesign.paper,
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
                                fontFamily: AnsibleDesign.serif,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AnsibleDesign.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const ElixSignedPill(kind: 'PK'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'SIGNED · PASSKEY',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 11,
                          letterSpacing: 1.3,
                          color: AnsibleDesign.ochre,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${text.localDid} · ${_shortDid(did)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 12.5,
                          color: AnsibleDesign.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EditProfileScreen(db: db, did: did),
                      ),
                    );
                  },
                  child: Text(
                    text.edit,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.sans,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AnsibleDesign.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onOpenPersonalBoard != null)
            _SettingsSection(
              label: context.uiCopy(zh: '我的內容', en: 'MY CONTENT'),
              children: [
                AnsibleSettingsRow(
                  key: const Key('settings_open_personal_board'),
                  glyph: '▤',
                  label: context.uiCopy(zh: '個人版', en: 'My board'),
                  en: 'PERSONAL BOARD',
                  sub: context.uiCopy(
                    zh: '你自己的貼文與筆記',
                    en: 'Your own posts and notes',
                  ),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    onOpenPersonalBoard!();
                  },
                ),
              ],
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
                      builder: (_) => SyncSettingsScreen(db: db, localDid: did),
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
              _IssuerToolsFold(did: did, capabilities: _capabilities),
              _IdentityCustodyRow(did: did, capabilities: _capabilities),
              AnsibleSettingsRow(
                key: const Key('settings_identity_security_row'),
                glyph: '⇄',
                label: context.uiCopy(
                  zh: '裝置與帳號復原',
                  en: 'Devices and account recovery',
                ),
                en: 'RECOVERY',
                sub: context.uiCopy(
                  zh: '新增、撤銷、恢復碼與安全紀錄',
                  en: 'Approve, revoke, recovery codes, and audit',
                ),
                last: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => IdentitySecurityScreen(db: db, did: did),
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
              _NotificationSettingsRow(
                text: text,
                db: db,
                did: did,
                capabilities: _capabilities,
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
          if (_showLocalAiAccess)
            _SettingsSection(
              label: context.uiCopy(zh: 'AI 存取', en: 'AI ACCESS'),
              children: [
                AnsibleSettingsRow(
                  key: const Key('settings_local_ai_access_row'),
                  glyph: '⌁',
                  label: context.uiCopy(zh: '本機 AI 存取', en: 'Local AI Access'),
                  en: 'LOCAL MCP',
                  sub: context.uiCopy(
                    zh: '讓本機 AI 客戶端讀取你選擇的內容',
                    en: 'Let local AI clients read content you choose',
                  ),
                  last: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LocalAiAccessScreen(db: db, did: did),
                      ),
                    );
                  },
                ),
              ],
            ),
          _SettingsSection(
            label: text.boundaries,
            children: [
              _RecoveryReadinessRow(
                text: text,
                did: did,
                store: recoveryReadinessStore,
                identityPrivateKeyProvider: identityPrivateKeyProvider,
              ),
              _RecoverAccountRow(
                db: db,
                did: did,
                recoveryReadinessStore: recoveryReadinessStore,
                onOpenRecoveryWizard: onOpenRecoveryWizard,
              ),
              _BlockedListSettingsRow(db: db, text: text, last: false),
              _ExternalContentSettingsRow(
                controller: externalContentPreferencesController,
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
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
                fontSize: 11,
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
