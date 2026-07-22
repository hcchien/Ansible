import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_l10n.dart';
import '../services/recovery_readiness_store.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// "Back up your identity" screen (recovery design Task 2 / D5-b).
///
/// The user enters a passphrase; we derive a key from it and encrypt the
/// identity (content) key into a self-describing blob they can copy/export.
///
/// Constitution must-haves honored here:
///   - backup is **opt-in**: nothing happens until the user types a passphrase
///     and taps the create button. We never auto-create or auto-upload.
///   - the passphrase-encrypted blob is the **only** form the key leaves the
///     device in; we display it for the user to save themselves. We do NOT
///     upload it anywhere in this slice.
///   - no raw legal identity is involved — only the Ed25519 key + DID.
///
/// TODO(Task 2/3): in production the identity private key MUST come from
/// secure storage (flutter_secure_storage / ansible_did), not be passed in.
/// [identityPrivateKeyHex] is injectable so this screen is testable now and so
/// the secure-storage read can be wired without touching the UI. Also add
/// export-as-QR and optional relay ciphertext storage (relay sees ciphertext
/// only) in later tasks.
class IdentityBackupScreen extends StatefulWidget {
  const IdentityBackupScreen({
    super.key,
    required this.did,
    required this.identityPrivateKeyHex,
    this.handle,
    this.readinessStore = const SharedPreferencesRecoveryReadinessStore(),
    this.onBackupCreated,
    this.encryptBackup = IdentityKeyBackup.encrypt,
  });

  final String did;

  /// The account handle, embedded as cleartext metadata in the blob so the
  /// backup is fully self-describing (blob + passphrase → which account).
  final String? handle;

  /// Provides the raw Ed25519 identity private key (hex). Injected for
  /// testability; production wiring reads it from secure storage.
  final Future<String?> Function() identityPrivateKeyHex;

  final RecoveryReadinessStore readinessStore;

  /// The encrypt function. Defaults to the real [IdentityKeyBackup.encrypt];
  /// injectable so widget tests can avoid the (real-timer) PBKDF2 path, which
  /// does not cooperate with the widget-test fake clock.
  final Future<String> Function({
    required String passphrase,
    required String identityPrivateKeyHex,
    String? did,
    String? handle,
  })
  encryptBackup;

  /// Called after a backup blob is successfully created (e.g. to refresh the
  /// settings readiness indicator).
  final VoidCallback? onBackupCreated;

  @override
  State<IdentityBackupScreen> createState() => _IdentityBackupScreenState();
}

class _IdentityBackupScreenState extends State<IdentityBackupScreen> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _working = false;
  String? _blob;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final pass = _passphrase.text;
    if (pass.isEmpty) {
      setState(
        () => _error = context.uiCopy(
          zh: '請先輸入備份密語。',
          en: 'Enter a backup passphrase first.',
        ),
      );
      return;
    }
    if (pass != _confirm.text) {
      setState(
        () => _error = context.uiCopy(
          zh: '兩次輸入的密語不一致。',
          en: 'The two passphrases do not match.',
        ),
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
      _blob = null;
    });
    try {
      final keyHex = await widget.identityPrivateKeyHex();
      if (keyHex == null) {
        throw StateError('No identity key available to back up.');
      }
      final blob = await widget.encryptBackup(
        passphrase: pass,
        identityPrivateKeyHex: keyHex,
        did: widget.did,
        handle: widget.handle,
      );
      await widget.readinessStore.markBackupCreated();
      widget.onBackupCreated?.call();
      if (!mounted) return;
      setState(() {
        _blob = blob;
        _working = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = context.uiCopy(
          zh: '建立備份時發生錯誤，請再試一次。',
          en: 'Could not create the backup. Please try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '備份身分', en: 'BACK UP IDENTITY'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      onLeading: () => Navigator.of(context).maybePop(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
        children: [
          Text(
            context.uiCopy(
              zh:
                  '用一句只有你知道的密語，把你的身分金鑰加密成一份備份。'
                  '備份只會以加密形式存在——沒有密語就無法解開。',
              en:
                  'Encrypt your identity key with a passphrase only you know. '
                  'The backup exists only in encrypted form — without the '
                  'passphrase it cannot be opened.',
            ),
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 18),
          _PassphraseField(
            key: const Key('backup_passphrase_field'),
            controller: _passphrase,
            label: context.uiCopy(zh: '備份密語', en: 'Backup passphrase'),
          ),
          const SizedBox(height: 12),
          _PassphraseField(
            key: const Key('backup_passphrase_confirm_field'),
            controller: _confirm,
            label: context.uiCopy(zh: '再次輸入密語', en: 'Confirm passphrase'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('backup_error_text'),
              style: const TextStyle(
                fontSize: 12.5,
                color: AnsibleDesign.ember,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _PrimaryButton(
            key: const Key('backup_create_button'),
            label: _working
                ? context.uiCopy(zh: '建立中…', en: 'Creating…')
                : context.uiCopy(zh: '建立加密備份', en: 'Create encrypted backup'),
            onPressed: _working ? null : _create,
          ),
          if (_blob != null) ...[
            const SizedBox(height: 24),
            AnsibleMonoLabel(
              context.uiCopy(zh: '你的加密備份', en: 'YOUR ENCRYPTED BACKUP'),
            ),
            const SizedBox(height: 8),
            Container(
              key: const Key('backup_blob_box'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AnsibleDesign.paperElev,
                border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _blob!,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10.5,
                  height: 1.4,
                  color: AnsibleDesign.ink,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _PrimaryButton(
              key: const Key('backup_copy_button'),
              label: context.uiCopy(zh: '複製備份', en: 'Copy backup'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _blob!));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.uiCopy(zh: '已複製備份', en: 'Backup copied'),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              context.uiCopy(
                zh:
                    '把這份備份存到安全的地方（密碼管理器、離線檔案）。'
                    '記住你的密語——遺失密語就無法復原。',
                en:
                    'Save this backup somewhere safe (a password manager, an '
                    'offline file). Remember your passphrase — if you lose it '
                    'the backup cannot be recovered.',
              ),
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PassphraseField extends StatelessWidget {
  const _PassphraseField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AnsibleDesign.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 12,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}
