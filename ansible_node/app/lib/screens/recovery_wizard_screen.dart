import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/identity_anchor_service.dart';
import '../services/relay_anchor_client.dart';
import '../theme/ansible_design.dart';
import 'recovery_from_device_screen.dart';
import '../widgets/ansible_screen_chrome.dart';

/// Recovery wizard — restore-from-backup path (recovery design Task 5, the
/// primary self-service flow).
///
/// Steps:
///   1. paste the encrypted backup blob + passphrase;
///   2. decrypt the identity key ([IdentityKeyBackup.decrypt]);
///   3. install it into secure storage (via [installRecoveredKey]);
///   4. generate a FRESH device key for this device + build a `reason:rotation`
///      anchor signed by the recovered identity key as both new sig and
///      device_sig (possession of the identity key = full authority,
///      immediate);
///   5. POST to the relay; on 200 persist the new anchor + flip readiness.
///
/// Constitution must-haves: restore is opt-in + passphrase-gated (nothing
/// happens until the user pastes a blob and types the passphrase); device
/// private keys never leave the device / never in backups (the device key is
/// generated locally and stored in secure storage only).
class RecoveryWizardScreen extends StatefulWidget {
  const RecoveryWizardScreen({
    super.key,
    required this.service,
    required this.installRecoveredKey,
    this.decryptBackup = IdentityKeyBackup.decrypt,
    this.identityKeyFactory = _defaultIdentityKeyFactory,
    this.onRecovered,
  });

  /// The anchor service used to fetch the active anchor + publish the rotation.
  final IdentityAnchorService service;

  /// Installs the decrypted identity private key (hex) into secure storage so
  /// the rest of the app picks it up. Injected for testability.
  final Future<void> Function(String privateKeyHex) installRecoveredKey;

  /// Decrypts the backup blob. Defaults to [IdentityKeyBackup.decrypt];
  /// injectable so widget tests can avoid the real (real-timer) PBKDF2 path.
  final Future<String> Function({
    required String passphrase,
    required String blobJson,
  })
  decryptBackup;

  /// Builds an [IdentityKey] from the decrypted private key hex.
  final IdentityKey Function(String privateKeyHex) identityKeyFactory;

  /// Called after a successful recovery (e.g. to refresh app identity state).
  final void Function(String did)? onRecovered;

  static IdentityKey _defaultIdentityKeyFactory(String privateKeyHex) =>
      InMemoryIdentityKey(privateKeyHex);

  @override
  State<RecoveryWizardScreen> createState() => _RecoveryWizardScreenState();
}

enum _Phase { input, working, recovered }

class _RecoveryWizardScreenState extends State<RecoveryWizardScreen> {
  final TextEditingController _blob = TextEditingController();
  final TextEditingController _passphrase = TextEditingController();
  _Phase _phase = _Phase.input;
  String? _error;
  String? _recoveredDid;

  @override
  void dispose() {
    _blob.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    final blobJson = _blob.text.trim();
    final passphrase = _passphrase.text;
    if (blobJson.isEmpty) {
      setState(
        () => _error = context.uiCopy(
          zh: '請先貼上你的加密備份。',
          en: 'Paste your encrypted backup first.',
        ),
      );
      return;
    }
    if (passphrase.isEmpty) {
      setState(
        () => _error = context.uiCopy(
          zh: '請輸入備份密語。',
          en: 'Enter your backup passphrase.',
        ),
      );
      return;
    }

    // Parse the blob up front so we know the DID/handle to re-anchor.
    final ParsedKeyBackup parsed;
    try {
      parsed = IdentityKeyBackup.parse(blobJson);
    } on BackupFormatException {
      setState(
        () => _error = context.uiCopy(
          zh: '這不是有效的 Elix 身分備份。',
          en: 'This is not a valid Elix identity backup.',
        ),
      );
      return;
    }
    final did = parsed.did;
    if (did == null) {
      setState(
        () => _error = context.uiCopy(
          zh: '備份缺少身分資訊，無法復原。',
          en: 'The backup is missing identity information.',
        ),
      );
      return;
    }

    setState(() {
      _phase = _Phase.working;
      _error = null;
    });

    try {
      // 1-2. Decrypt the identity key (passphrase-gated).
      final privateKeyHex = await widget.decryptBackup(
        passphrase: passphrase,
        blobJson: blobJson,
      );

      // 3. Fetch the current active anchor to chain against.
      final previous = await widget.service.relayClient.fetchActiveAnchor(did);
      if (previous == null) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.input;
          _error = context.uiCopy(
            zh: '在伺服器上找不到這個身分的錨定紀錄。',
            en: 'No anchor record was found for this identity on the server.',
          );
        });
        return;
      }

      // 4. Install the recovered key, build + publish the rotation anchor.
      await widget.installRecoveredKey(privateKeyHex);
      final identityKey = widget.identityKeyFactory(privateKeyHex);
      final result = await widget.service.recoverFromBackupRotation(
        did: did,
        handle: previous.handle,
        identityKey: identityKey,
        previous: previous,
      );

      if (!mounted) return;
      if (result.relayResult.state == AnchorState.active) {
        widget.onRecovered?.call(did);
        setState(() {
          _phase = _Phase.recovered;
          _recoveredDid = did;
        });
      } else {
        setState(() {
          _phase = _Phase.input;
          _error = context.uiCopy(
            zh: '伺服器尚未接受這次復原，請稍後再試。',
            en: 'The server did not accept the recovery yet. Please try again.',
          );
        });
      }
    } on BackupDecryptException {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error = context.uiCopy(
          zh: '密語錯誤或備份已損毀。',
          en: 'Wrong passphrase or corrupted backup.',
        );
      });
    } on RelayAnchorException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error = userFacingError(context, e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.input;
        _error = userFacingError(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '使用既有帳號', en: 'USE EXISTING ACCOUNT'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      onLeading: () => Navigator.of(context).maybePop(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
        children: _phase == _Phase.recovered
            ? _recoveredContent(context)
            : _inputContent(context),
      ),
    );
  }

  List<Widget> _inputContent(BuildContext context) {
    final working = _phase == _Phase.working;
    return [
      Text(
        context.uiCopy(
          zh:
              '貼上你之前建立的加密備份，並輸入備份密語。'
              '我們會在這台裝置上解開你的身分金鑰，'
              '並為這台裝置產生一把全新的裝置金鑰，重新錨定你的帳號。',
          en:
              'Paste the encrypted backup you created earlier and enter its '
              'passphrase. We unlock your identity key on this device, '
              'generate a fresh device key for it, and re-anchor your account.',
        ),
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AnsibleDesign.inkMuted,
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('recovery_blob_field'),
        controller: _blob,
        minLines: 4,
        maxLines: 8,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: context.uiCopy(zh: '加密備份', en: 'Encrypted backup'),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('recovery_passphrase_field'),
        controller: _passphrase,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: context.uiCopy(zh: '備份密語', en: 'Backup passphrase'),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          key: const Key('recovery_error_text'),
          style: const TextStyle(fontSize: 12.5, color: AnsibleDesign.ember),
        ),
      ],
      const SizedBox(height: 20),
      _PrimaryButton(
        key: const Key('recovery_submit_button'),
        label: working
            ? context.uiCopy(zh: '復原中…', en: 'Recovering…')
            : context.uiCopy(zh: '復原我的帳號', en: 'Recover my account'),
        onPressed: working ? null : _recover,
      ),
      const SizedBox(height: 22),
      // Approve-from-other-device (design flow 3a): no backup needed when an
      // old, enrolled device survives.
      Center(
        child: TextButton(
          key: const Key('recovery_from_device_entry'),
          onPressed: working
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecoveryFromDeviceScreen(
                        installRecoveredKey: widget.installRecoveredKey,
                      ),
                    ),
                  );
                },
          child: Text(
            context.uiCopy(
              zh: '沒有備份？用另一台裝置核可',
              en: 'No backup? Approve from another device',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 14,
              color: AnsibleDesign.inkMuted,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _recoveredContent(BuildContext context) {
    return [
      const SizedBox(height: 12),
      const Icon(
        Icons.verified_user_outlined,
        size: 40,
        color: AnsibleDesign.spore,
      ),
      const SizedBox(height: 16),
      Text(
        context.uiCopy(zh: '帳號已復原', en: 'Account recovered'),
        key: const Key('recovery_success_text'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AnsibleDesign.ink,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        context.uiCopy(
          zh:
              '你的身分金鑰已重新安裝到這台裝置，並已產生一把新的裝置金鑰。'
              '舊裝置的金鑰不會被復原（它從不備份）。',
          en:
              'Your identity key has been reinstalled on this device and a new '
              'device key has been enrolled. The old device key is not '
              'recovered (it is never backed up).',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: AnsibleDesign.inkMuted,
        ),
      ),
      if (_recoveredDid != null) ...[
        const SizedBox(height: 12),
        Text(
          _recoveredDid!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 11,
            color: AnsibleDesign.inkFaint,
          ),
        ),
      ],
      const SizedBox(height: 24),
      _PrimaryButton(
        key: const Key('recovery_done_button'),
        label: context.uiCopy(zh: '完成', en: 'Done'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ];
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
