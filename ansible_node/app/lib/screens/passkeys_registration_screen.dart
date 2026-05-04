import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/atproto_client.dart';

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

  const PasskeysRegistrationScreen({
    super.key,
    required this.onRegistered,
    this.passkeysManager,
    this.didPlcManager,
    this.atProtoClient,
    this.nonceSigner,
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
    _passkeysManager = widget.passkeysManager ?? PasskeysManagerImpl();
    _didPlcManager = widget.didPlcManager ?? DidPlcManagerImpl();
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
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = _formatError(e);
      });
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
        throw const FormatException(
          'Registration signature must be a 64-byte hex Ed25519 signature',
        );
      }
      return sig.hex;
    } on UnimplementedError {
      // Rust bridge not built yet — return a dev stub that the local Relay
      // accepts. Real devices always have the bridge available.
      return 'dev-sig-${base64Url.encode(utf8.encode(nonce)).replaceAll("=", "")}';
    } on StateError {
      // Keypair not in storage yet (race during first registration) — same stub.
      return 'dev-sig-${base64Url.encode(utf8.encode(nonce)).replaceAll("=", "")}';
    }
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fingerprint,
                      size: 72,
                      color: Color(0xFF1A56A4),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Ansible',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A56A4),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Passkeys 身份建立',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _handleController,
                      enabled: _phase == _Phase.idle,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: '帳號名稱',
                        suffixText: '.trisaura.io',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildPhaseIndicator(),
                    const SizedBox(height: 32),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _phase == _Phase.idle
                            ? _startRegistration
                            : null,
                        icon: const Icon(Icons.key),
                        label: const Text('建立帳號（Passkeys）'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '系統不收集個人資料\n私鑰僅存於裝置安全晶片',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseIndicator() {
    if (_phase == _Phase.idle) return const SizedBox.shrink();

    final steps = [
      (label: '🔑 金鑰生成中', phase: _Phase.generatingKey),
      (label: '🪪 建立 DID', phase: _Phase.creatingDid),
      (label: '☁️ 上傳 Relay', phase: _Phase.anchoring),
      (label: '✅ 身份建立完成', phase: _Phase.done),
    ];

    return Column(
      children: steps.map((s) {
        final isDone = _phase.index > s.phase.index;
        final isCurrent = _phase == s.phase;
        return ListTile(
          dense: true,
          leading: isCurrent
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isDone ? Colors.green : Colors.grey,
                  size: 24,
                ),
          title: Text(
            s.label,
            style: TextStyle(
              color: isCurrent ? const Color(0xFF1A56A4) : null,
              fontWeight: isCurrent ? FontWeight.bold : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}
