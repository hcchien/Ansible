import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../l10n/app_l10n.dart';
import '../services/identity_anchor_service.dart';
import '../services/recovery_readiness_store.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'identity_backup_screen.dart';

/// Post-registration onboarding step (recovery design Task 2: "offer at first
/// run + nag-once").
///
/// Wired immediately after the v2 challenge-anchor succeeds (which claims the
/// handle + did_accounts). This step:
///   1. publishes the initial self-certifying anchor via
///      [IdentityAnchorService.publishInitialAnchor] so the anchor-object chain
///      that recovery/re-anchor needs exists on the relay — FAILURE-TOLERANT:
///      the account already works (the v2 anchor claimed the handle), so a
///      failure here only means "recovery isn't set up yet", surfaced to the
///      user; it never blocks completing onboarding.
///   2. STRONGLY offers an encrypted backup (opt-in / skippable, Constitution
///      must-have). Creating one re-uses [IdentityBackupScreen]; skipping sets a
///      "nag once later" flag and shows a clear data-loss warning.
///
/// Whether the user backs up or skips, onboarding completes via [onComplete] —
/// a missing backup must never lock the user out of their own new account.
class OnboardingBackupStepScreen extends StatefulWidget {
  const OnboardingBackupStepScreen({
    super.key,
    required this.did,
    required this.handle,
    required this.anchorService,
    required this.onComplete,
    this.identityPrivateKeyHex = _defaultIdentityPrivateKey,
    this.identityKeyForAnchor,
    this.readinessStore = const SharedPreferencesRecoveryReadinessStore(),
    this.autoPublishAnchor = true,
  });

  final String did;
  final String handle;

  /// Service used to publish the initial self-certifying anchor.
  final IdentityAnchorService anchorService;

  /// Completes onboarding (enters the app under [did]). Always called eventually
  /// regardless of backup outcome.
  final void Function(String did) onComplete;

  /// Reads the raw Ed25519 identity private key (hex) from secure storage —
  /// fed to [IdentityBackupScreen] for the backup blob. Injected for tests.
  final Future<String?> Function() identityPrivateKeyHex;

  /// The identity key used to sign the initial anchor. Defaults to
  /// [SecureStorageIdentityKey]; injectable for tests.
  final IdentityKey? identityKeyForAnchor;

  final RecoveryReadinessStore readinessStore;

  /// When false, skips the publishInitialAnchor call (used by widget tests that
  /// don't want to drive the relay). Production always leaves this true.
  final bool autoPublishAnchor;

  static Future<String?> _defaultIdentityPrivateKey() {
    return const FlutterSecureStorage().read(key: 'ansible_did_private_key');
  }

  @override
  State<OnboardingBackupStepScreen> createState() =>
      _OnboardingBackupStepScreenState();
}

class _OnboardingBackupStepScreenState
    extends State<OnboardingBackupStepScreen> {
  /// Null = anchor publish not finished; true = ok; false = failed (recovery
  /// chain not set up, but the account still works).
  bool? _anchorPublished;

  @override
  void initState() {
    super.initState();
    if (widget.autoPublishAnchor) {
      _publishInitialAnchor();
    } else {
      _anchorPublished = true;
    }
  }

  Future<void> _publishInitialAnchor() async {
    try {
      final identityKey =
          widget.identityKeyForAnchor ?? const SecureStorageIdentityKey();
      await widget.anchorService.publishInitialAnchor(
        did: widget.did,
        handle: widget.handle,
        identityKey: identityKey,
      );
      if (!mounted) return;
      setState(() => _anchorPublished = true);
    } catch (e, st) {
      // Failure-tolerant: the v2 anchor already claimed the handle so the
      // account works. We only lose the self-certifying chain recovery needs,
      // which we surface below.
      debugPrint('[ONBOARDING ANCHOR] publishInitialAnchor failed: $e\n$st');
      if (!mounted) return;
      setState(() => _anchorPublished = false);
    }
  }

  Future<void> _createBackup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IdentityBackupScreen(
          did: widget.did,
          handle: widget.handle,
          identityPrivateKeyHex: widget.identityPrivateKeyHex,
          readinessStore: widget.readinessStore,
        ),
      ),
    );
    if (!mounted) return;
    // If the user actually produced a backup, complete onboarding into the app.
    // Otherwise they backed out — stay on this step so they can retry or skip.
    if (await widget.readinessStore.hasBackup() && mounted) {
      widget.onComplete(widget.did);
    }
  }

  Future<void> _skip() async {
    // Opt-in / skippable: remember the skip so we nag once on a later launch.
    await widget.readinessStore.markBackupSkipped();
    if (!mounted) return;
    widget.onComplete(widget.did);
  }

  String _copy({required String zh, required String en}) {
    return context.uiCopy(zh: zh, en: en);
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: _copy(zh: '保護你的帳號', en: 'PROTECT YOUR ACCOUNT'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 40, color: AnsibleDesign.spore),
          const SizedBox(height: 16),
          Text(
            _copy(zh: '帳號已建立', en: 'Account created'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AnsibleDesign.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.handle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 12,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _copy(
              zh: '現在做一份加密備份。沒有備份的話，'
                  '如果你弄丟這台裝置，就無法復原這個帳號。',
              en: 'Make an encrypted backup now. Without a backup you cannot '
                  'recover this account if you lose this device.',
            ),
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: AnsibleDesign.ink,
            ),
          ),
          if (_anchorPublished == false) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('onboarding_anchor_warning'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AnsibleDesign.ember.withValues(alpha: 0.08),
                border: Border.all(
                  color: AnsibleDesign.ember.withValues(alpha: 0.25),
                  width: 0.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _copy(
                  zh: '⚠ 復原機制尚未在伺服器上完成設定，帳號仍可正常使用。'
                      '之後可在「設定 → 復原」重試。',
                  en: '⚠ Account recovery is not fully set up on the server yet. '
                      'Your account still works; you can retry later in '
                      'Settings → Recovery.',
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AnsibleDesign.ember,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _PrimaryButton(
            key: const Key('onboarding_backup_button'),
            label: _copy(zh: '建立加密備份', en: 'Create encrypted backup'),
            onPressed: _createBackup,
          ),
          const SizedBox(height: 10),
          TextButton(
            key: const Key('onboarding_skip_button'),
            onPressed: _skip,
            child: Text(
              _copy(zh: '稍後再說', en: 'Maybe later'),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 12,
                letterSpacing: 1.1,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
        ],
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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
