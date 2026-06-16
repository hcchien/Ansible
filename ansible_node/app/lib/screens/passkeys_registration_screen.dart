import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/atproto_client.dart';
import '../theme/ansible_design.dart';

/// Passkeys Registration Screen — Phase 1 V2.0
///
/// Guides the user through:
///   1. Biometric / Passkeys key generation (Secure Enclave / StrongBox)
///   2. did:plc creation via Rust FFI
///   3. DID registration + anchoring with Relay
///   4. → HomeShell

enum _Phase { idle, generatingKey, creatingDid, anchoring, done }

class PasskeysRegistrationScreen extends StatefulWidget {
  /// Called with the anchored DID + handle when registration completes (the v2
  /// challenge-anchor has claimed the handle). Carries the handle so the
  /// onboarding backup step can build a self-describing backup blob.
  final void Function(String did, String handle) onRegistered;

  /// Opens the "recover an existing account" flow (the [RecoveryWizardScreen]).
  /// Wired by the host (main.dart) so this screen stays routing-agnostic.
  final VoidCallback? onRecoverExistingAccount;

  // Testable injections — if null, default implementations are used.
  final PasskeysManager? passkeysManager;
  final DidPlcManager? didPlcManager;
  final AtProtoClient? atProtoClient;
  final Future<String> Function(String nonce, String publicKeyHex)? nonceSigner;
  final bool allowInsecureDevFallback;

  const PasskeysRegistrationScreen({
    super.key,
    required this.onRegistered,
    this.onRecoverExistingAccount,
    this.passkeysManager,
    this.didPlcManager,
    this.atProtoClient,
    this.nonceSigner,
    this.allowInsecureDevFallback =
        AppEnvironment.allowInsecureIdentityFallback,
  });

  @override
  State<PasskeysRegistrationScreen> createState() =>
      _PasskeysRegistrationScreenState();
}

class _PasskeysRegistrationScreenState
    extends State<PasskeysRegistrationScreen> {
  _Phase _phase = _Phase.idle;
  String? _errorMessage;
  final TextEditingController _handleController = TextEditingController(
    text: AppEnvironment.defaultHandleSuffix,
  );

  late final PasskeysManager _passkeysManager;
  late final DidPlcManager _didPlcManager;
  late final AtProtoClient _atProtoClient;

  @override
  void initState() {
    super.initState();
    _passkeysManager =
        widget.passkeysManager ??
        PasskeysManagerImpl(
          allowInsecureFallback: widget.allowInsecureDevFallback,
        );
    _didPlcManager =
        widget.didPlcManager ??
        DidPlcManagerImpl(
          allowInsecureFallback: widget.allowInsecureDevFallback,
        );
    _atProtoClient = widget.atProtoClient ?? AtProtoClient();
  }

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _startRegistration() async {
    final handleSuffix = _normalizeHandleSuffix(_handleController.text);
    if (handleSuffix == null) {
      setState(() {
        _errorMessage = _copy(
          zh: '帳號名稱格式無效，請使用 1–63 個英數字或中間連字號。',
          en: 'Account name format is invalid. Use 1-63 letters, numbers, or middle hyphens.',
        );
      });
      return;
    }
    final handle = '$handleSuffix.elix.cool';

    setState(() {
      _phase = _Phase.generatingKey;
      _errorMessage = null;
    });

    try {
      // ── Step 1: Biometric / Passkeys key generation ─────────────────────
      final credential = await _passkeysManager.register(
        username: handleSuffix,
      );

      // ── Step 2: did:plc creation via Rust FFI ───────────────────────────
      setState(() => _phase = _Phase.creatingDid);
      final didResult = await _didPlcManager.createDid(
        handle: handle,
        signingKeyHex: credential.publicKeyHex,
      );

      // ── Step 3: Register + anchor with Relay ────────────────────────────
      setState(() => _phase = _Phase.anchoring);

      try {
        final challenge = await _atProtoClient.register(
          publicKeyHex: credential.publicKeyHex,
          handleSuffix: handleSuffix,
        );
        if (challenge.handle != null && challenge.handle != handle) {
          throw StateError(
            'Relay returned a different handle for this registration.',
          );
        }

        // Sign the nonce with the DID private key so the Relay can verify
        // ownership of the public key presented during register().
        final registrationSig = await (widget.nonceSigner ?? _signNonce)(
          challenge.nonce,
          credential.publicKeyHex,
        );

        final result = await _atProtoClient.anchor(
          AnchorRequest(
            did: didResult.did,
            publicKeyHex: credential.publicKeyHex,
            handle: handle,
            registrationSig: registrationSig,
            nonce: challenge.nonce,
          ),
        );

        // ── Step 4: Done ─────────────────────────────────────────────────────
        setState(() => _phase = _Phase.done);
        widget.onRegistered(result.did, handle);
      } catch (e) {
        if (!_canCompleteLocalOnly(e)) rethrow;
        setState(() => _phase = _Phase.done);
        widget.onRegistered(didResult.did, handle);
      }
    } catch (e, st) {
      // Keep the on-device diagnostic in the logs for triage; do NOT leak the
      // raw exception into the user-facing message.
      debugPrint('[REGISTRATION ERROR] ${e.runtimeType}: $e\n$st');
      await _cleanupPartialRegistration();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = _formatError(e);
      });
    }
  }

  bool _canCompleteLocalOnly(Object error) {
    if (!widget.allowInsecureDevFallback) return false;
    return error is! AtProtoException;
  }

  Future<void> _cleanupPartialRegistration() async {
    try {
      await _didPlcManager.deleteDid();
    } catch (_) {
      // Keep the original registration error visible.
    }
    try {
      await _passkeysManager.delete();
    } catch (_) {
      // Keep the original registration error visible.
    }
  }

  /// Sign [nonce] with the Ed25519 private key stored in Secure Enclave.
  ///
  /// The Relay verifies this signature against [publicKeyHex] in the anchor
  /// request, proving the client controls the private key it claims to own.
  ///
  /// Falls back to a dev stub when the Rust bridge is not yet initialised
  /// (UnimplementedError) or when no keypair has been written to storage yet
  /// (StateError). The stub is accepted by the Relay only in dev/local mode.
  Future<String> _signNonce(String nonce, String publicKeyHex) async {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(publicKeyHex)) {
      throw const FormatException(
        'Registration public key must be 32-byte hex.',
      );
    }
    try {
      final signer = DidSignerImpl(secureStorage: const FlutterSecureStorage());
      final sig = await signer.sign(utf8.encode(nonce));
      if (!RegExp(r'^[0-9a-fA-F]{128}$').hasMatch(sig.hex)) {
        if (widget.allowInsecureDevFallback) {
          return _devSignatureForNonce(nonce);
        }
        throw const FormatException(
          'Registration signature must be a 64-byte hex Ed25519 signature',
        );
      }
      return sig.hex;
    } on UnimplementedError {
      // Rust bridge not built yet — return a dev stub that the local Relay
      // accepts. Real devices always have the bridge available.
      if (!widget.allowInsecureDevFallback) rethrow;
      return _devSignatureForNonce(nonce);
    } on StateError {
      // Keypair not in storage yet (race during first registration) — same stub.
      if (!widget.allowInsecureDevFallback) rethrow;
      return _devSignatureForNonce(nonce);
    }
  }

  String _devSignatureForNonce(String nonce) {
    return 'dev-sig-${base64Url.encode(utf8.encode(nonce)).replaceAll("=", "")}';
  }

  String? _normalizeHandleSuffix(String raw) {
    final value = raw.trim().toLowerCase();
    final valid = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');
    return valid.hasMatch(value) ? value : null;
  }

  String _formatError(Object error) {
    if (error is AtProtoException) {
      switch (error.error) {
        case 'duplicate_did':
        case 'handle_taken':
        case 'handle_pending':
          return _copy(
            zh: '此帳號名稱已被使用，請嘗試不同的名稱。',
            en: 'This account name is already in use. Try another name.',
          );
        case 'handle_mismatch':
          return _copy(
            zh: '帳號名稱不一致，請重新開始。',
            en: 'Account name mismatch. Start again.',
          );
        case 'invalid_public_key':
          return _copy(
            zh: '金鑰格式無效，請重新嘗試。',
            en: 'Invalid key format. Try again.',
          );
        case 'invalid_nonce':
        case 'expired_nonce':
          return _copy(
            zh: '驗證碼已失效，請重新開始。',
            en: 'Verification code expired. Start again.',
          );
        case 'invalid_sig':
        case 'invalid_signature':
        case 'signature_mismatch':
          return _copy(
            zh: '簽章驗證失敗，請重新嘗試。',
            en: 'Signature verification failed. Try again.',
          );
        case 'rate_limited':
          return _copy(
            zh: '請求過於頻繁，請稍後再試。',
            en: 'Too many requests. Try again later.',
          );
        case 'server_error':
          return _copy(
            zh: '伺服器錯誤，請稍後再試。',
            en: 'Server error. Try again later.',
          );
      }
      if (error.statusCode >= 500) {
        return _copy(
          zh: '伺服器暫時無法使用，請稍後再試。',
          en: 'Server is temporarily unavailable. Try again later.',
        );
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return _copy(
          zh: '權限不足，請重新啟動應用程式。',
          en: 'Permission denied. Restart the app.',
        );
      }
    }
    if (error is PasskeysAuthException) {
      return _copy(
        zh: '裝置驗證未完成，請確認已啟用 Face ID、Touch ID 或裝置密碼。',
        en: 'Device authentication was not completed. Enable Face ID, Touch ID, or device passcode.',
      );
    }
    if (error is DidPlcException) {
      return _copy(
        zh: 'DID 建立尚未完成 production 設定，請確認原生 Rust bridge 已正確打包。',
        en: 'DID creation is not production-ready yet. Confirm that the native Rust bridge is bundled correctly.',
      );
    }
    if (error is FormatException) {
      return _copy(
        zh: '簽章格式無效，請重新嘗試。',
        en: 'Invalid signature format. Try again.',
      );
    }
    if (error is StateError) {
      return _copy(
        zh: '註冊狀態不一致，請重新開始。',
        en: 'Registration state is inconsistent. Start again.',
      );
    }
    return userFacingError(context, error);
  }

  String _copy({required String zh, required String en}) {
    return context.uiCopy(zh: zh, en: en);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Text(
                              '1 / 3',
                              style: TextStyle(
                                fontFamily: AnsibleDesign.mono,
                                fontSize: 10,
                                color: AnsibleDesign.inkFaint,
                                letterSpacing: 1.4,
                              ),
                            ),
                            Spacer(),
                            Text(
                              'SOCIAL FIRST',
                              style: TextStyle(
                                fontFamily: AnsibleDesign.mono,
                                fontSize: 10,
                                color: AnsibleDesign.inkFaint,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 36),
                        const AnsibleMark(
                          size: 86,
                          color: AnsibleDesign.accent,
                        ),
                        const SizedBox(height: 22),
                        const ElixWordmark(fontSize: 38),
                        const SizedBox(height: 22),
                        Text(
                          _copy(
                            zh: '先建立身分，\n再開始社群。',
                            en: 'Create identity first,\nthen join the community.',
                          ),
                          style: const TextStyle(
                            fontSize: 23,
                            height: 1.5,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _copy(
                            zh: 'Elix 是重視身分的社群 App。你追蹤的人、訂閱的板、以及你發出的 Note 與 Murmur，會一起形成動態。',
                            en: 'Elix is an identity-centered social app. People you follow, boards you subscribe to, and your Notes and Murmurs form the feed together.',
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.7,
                            color: AnsibleDesign.inkMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AnsibleDesign.rule,
                              width: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: AnsibleDesign.paperElev,
                          ),
                          child: Column(
                            children: [
                              _PromiseRow(
                                dot: AnsibleDesign.spore,
                                label: _copy(
                                  zh: '身分在你這裡',
                                  en: 'Identity stays with you',
                                ),
                                meta: 'IDENTITY',
                                body: _copy(
                                  zh: 'Elix 不會替你保管你的身分。每一次公開發文都由你的裝置簽出。',
                                  en: 'Elix does not custody your identity. Every public post is signed by your device.',
                                ),
                              ),
                              const Divider(height: 1),
                              _PromiseRow(
                                dot: AnsibleDesign.accent,
                                label: _copy(zh: '社群是首頁', en: 'Feed is home'),
                                meta: 'FEED',
                                body: _copy(
                                  zh: 'Murmur 與 Note 是個人版發文類型；追蹤你的人會在他們的 feed 上看到。',
                                  en: 'Murmur and Note are personal-board post types; followers see them in their feed.',
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  4,
                                  14,
                                  14,
                                ),
                                child: TextField(
                                  controller: _handleController,
                                  enabled: _phase == _Phase.idle,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: _copy(
                                      zh: '帳號名稱',
                                      en: 'Account name',
                                    ),
                                    suffixText: '.elix.cool',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPhaseIndicator(),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AnsibleDesign.danger.withValues(
                                alpha: 0.08,
                              ),
                              border: Border.all(
                                color: AnsibleDesign.danger.withValues(
                                  alpha: 0.25,
                                ),
                                width: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: AnsibleDesign.danger,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                  decoration: const BoxDecoration(
                    color: AnsibleDesign.paper,
                    border: Border(
                      top: BorderSide(
                        color: AnsibleDesign.ruleSoft,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _phase == _Phase.idle
                              ? _startRegistration
                              : null,
                          icon: const Icon(Icons.key_outlined),
                          label: Text(
                            _copy(
                              zh: '建立帳號（Passkeys）',
                              en: 'Create Account (Passkeys)',
                            ),
                          ),
                        ),
                      ),
                      if (widget.onRecoverExistingAccount != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          key: const Key('recover_existing_account_button'),
                          onPressed: _phase == _Phase.idle
                              ? widget.onRecoverExistingAccount
                              : null,
                          child: Text(
                            _copy(
                              zh: '已經有帳號？從備份復原',
                              en: 'Recover an existing account',
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AnsibleDesign.inkMuted,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        _copy(
                          zh: '重視身分的社群 App · 由 passkey 支撐',
                          en: 'Identity-centered social app · powered by passkeys',
                        ),
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 9,
                          color: AnsibleDesign.inkFaint,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseIndicator() {
    if (_phase == _Phase.idle) return const SizedBox.shrink();

    final steps = [
      (
        label: _copy(zh: 'PASSKEY · 金鑰生成中', en: 'PASSKEY · GENERATING KEY'),
        phase: _Phase.generatingKey,
      ),
      (
        label: _copy(zh: 'DID · 建立本地身份', en: 'DID · CREATING LOCAL IDENTITY'),
        phase: _Phase.creatingDid,
      ),
      (
        label: _copy(zh: 'RELAY · 錨定名稱', en: 'RELAY · ANCHORING HANDLE'),
        phase: _Phase.anchoring,
      ),
      (
        label: _copy(zh: 'DONE · 身份建立完成', en: 'DONE · IDENTITY CREATED'),
        phase: _Phase.done,
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        children: steps.map((s) {
          final isDone = _phase.index > s.phase.index;
          final isCurrent = _phase == s.phase;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                if (isCurrent)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Icon(
                    isDone ? Icons.check_circle : Icons.circle_outlined,
                    color: isDone
                        ? AnsibleDesign.spore
                        : AnsibleDesign.inkFaint,
                    size: 14,
                  ),
                const SizedBox(width: 10),
                Text(
                  s.label,
                  style: TextStyle(
                    color: isCurrent
                        ? AnsibleDesign.ink
                        : AnsibleDesign.inkMuted,
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 10,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({
    required this.dot,
    required this.label,
    required this.meta,
    required this.body,
  });

  final Color dot;
  final String label;
  final String meta;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 8.5,
                        color: AnsibleDesign.inkFaint,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
