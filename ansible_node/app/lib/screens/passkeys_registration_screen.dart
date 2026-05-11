import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  /// Called with the anchored DID string when registration completes.
  final void Function(String did) onRegistered;

  // Testable injections — if null, default implementations are used.
  final PasskeysManager? passkeysManager;
  final DidPlcManager? didPlcManager;
  final AtProtoClient? atProtoClient;
  final Future<String> Function(String nonce, String publicKeyHex)? nonceSigner;
  final bool allowInsecureDevFallback;

  const PasskeysRegistrationScreen({
    super.key,
    required this.onRegistered,
    this.passkeysManager,
    this.didPlcManager,
    this.atProtoClient,
    this.nonceSigner,
    this.allowInsecureDevFallback = const bool.fromEnvironment(
      'ANSIBLE_ALLOW_INSECURE_DEV_FALLBACK',
      defaultValue: true,
    ),
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
    text: const String.fromEnvironment(
      'ANSIBLE_DEFAULT_HANDLE_SUFFIX',
      defaultValue: 'user',
    ),
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
        _errorMessage = '帳號名稱格式無效，請使用 1–63 個英數字或中間連字號。';
      });
      return;
    }
    final handle = '$handleSuffix.trisaura.io';

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
        widget.onRegistered(result.did);
      } catch (e) {
        if (!_canCompleteLocalOnly(e)) rethrow;
        setState(() => _phase = _Phase.done);
        widget.onRegistered(didResult.did);
      }
    } catch (e) {
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
          return '此帳號名稱已被使用，請嘗試不同的名稱。';
        case 'handle_mismatch':
          return '帳號名稱不一致，請重新開始。';
        case 'invalid_public_key':
          return '金鑰格式無效，請重新嘗試。';
        case 'invalid_nonce':
        case 'expired_nonce':
          return '驗證碼已失效，請重新開始。';
        case 'invalid_sig':
        case 'invalid_signature':
        case 'signature_mismatch':
          return '簽章驗證失敗，請重新嘗試。';
        case 'rate_limited':
          return '請求過於頻繁，請稍後再試。';
        case 'server_error':
          return '伺服器錯誤，請稍後再試。';
      }
      if (error.statusCode >= 500) {
        return '伺服器暫時無法使用，請稍後再試。';
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return '權限不足，請重新啟動應用程式。';
      }
    }
    if (error is PasskeysAuthException) {
      return '裝置驗證未完成，請確認已啟用 Face ID、Touch ID 或裝置密碼。';
    }
    if (error is DidPlcException) {
      return 'DID 建立尚未完成 production 設定，請確認原生 Rust bridge 已正確打包。';
    }
    if (error is FormatException) {
      return '簽章格式無效，請重新嘗試。';
    }
    if (error is StateError) {
      return '註冊狀態不一致，請重新開始。';
    }
    return error.toString();
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
                              '本地優先',
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
                        const Text(
                          '在這裡，\n先慢一點。',
                          style: TextStyle(
                            fontSize: 23,
                            height: 1.5,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          '一個給碎念、筆記、與不急著被聽見的話的地方。先寫給自己；如果哪天想讓人看見，你會知道的。',
                          style: TextStyle(
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
                              const _PromiseRow(
                                dot: AnsibleDesign.spore,
                                label: '留在你這裡',
                                meta: 'STAYS LOCAL',
                                body: '碎念、筆記、草稿與沒寄出的句子，預設只在你的裝置裡。',
                              ),
                              const Divider(height: 1),
                              const _PromiseRow(
                                dot: AnsibleDesign.accent,
                                label: '送出前會先問你',
                                meta: 'ASKS FIRST',
                                body: '請 AI 整理、分享到圈子或公開之前，都會清楚列出會離開裝置的內容。',
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
                                  decoration: const InputDecoration(
                                    labelText: '帳號名稱',
                                    suffixText: '.trisaura.io',
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
                          label: const Text('建立帳號（Passkeys）'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '沒有帳號 · 沒有雲端 · 不會被收集',
                        style: TextStyle(
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
      (label: 'PASSKEY · 金鑰生成中', phase: _Phase.generatingKey),
      (label: 'DID · 建立本地身份', phase: _Phase.creatingDid),
      (label: 'RELAY · 錨定名稱', phase: _Phase.anchoring),
      (label: 'DONE · 身份建立完成', phase: _Phase.done),
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
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AnsibleDesign.ink,
                      ),
                    ),
                    const Spacer(),
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
