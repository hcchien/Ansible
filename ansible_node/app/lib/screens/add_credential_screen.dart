import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../services/atproto_client.dart';
import '../services/vc_issuer_client.dart';

/// Add Credential Screen — V2.0 Email Verification flow
///
/// Steps:
///   1. User enters email → POST /api/v1/vc/request
///   2. OTP field appears (mock mode: auto-filled)
///   3. User submits OTP  → POST /api/v1/vc/issue
///   4. VC stored in [CredentialWallet]
///   5. VP built + POSTed to Relay → reputation tier upgraded
///   6. onCredentialAdded called with final reputation tier

enum _Phase { idle, requesting, waitingOtp, issuing, presenting, done }

class AddCredentialScreen extends StatefulWidget {
  /// The holder's DID (from registration).
  final String holderDid;

  /// Called when the full flow completes (VC stored + VP accepted by Relay).
  /// [reputationTier] is the tier returned by the Relay, e.g. "verified_human".
  final void Function(String reputationTier) onCredentialAdded;

  // Testable injections
  final VcIssuerClient? vcIssuerClient;
  final AtProtoClient? relayClient;
  final CredentialWallet? credentialWallet;
  final VpBuilder? vpBuilder;

  const AddCredentialScreen({
    super.key,
    required this.holderDid,
    required this.onCredentialAdded,
    this.vcIssuerClient,
    this.relayClient,
    this.credentialWallet,
    this.vpBuilder,
  });

  @override
  State<AddCredentialScreen> createState() =>
      _AddCredentialScreenState();
}

class _AddCredentialScreenState extends State<AddCredentialScreen> {
  _Phase _phase = _Phase.idle;
  String? _errorMessage;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  late final VcIssuerClient _vcClient;
  late final AtProtoClient _relayClient;
  late final CredentialWallet _wallet;
  late final VpBuilder _vpBuilder;

  @override
  void initState() {
    super.initState();
    _vcClient = widget.vcIssuerClient ?? VcIssuerClient();
    _relayClient = widget.relayClient ?? AtProtoClient();
    _wallet = widget.credentialWallet ?? const CredentialWallet();
    _vpBuilder = widget.vpBuilder ?? VpBuilder();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // ── Step 1: Request OTP ────────────────────────────────────────────────────

  Future<void> _requestOtp() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _errorMessage = '請輸入有效的 Email 地址。');
      return;
    }

    setState(() {
      _phase = _Phase.requesting;
      _errorMessage = null;
    });

    try {
      final challenge = await _vcClient.requestEmailVerification(
        did: widget.holderDid,
        email: email,
      );

      setState(() {
        _phase = _Phase.waitingOtp;
        // In mock mode the server returns the OTP directly
        if (challenge.isMockOtp) {
          _otpController.text = challenge.otp!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _errorMessage = _formatError(e);
      });
    }
  }

  // ── Step 2: Submit OTP → issue VC → present VP ────────────────────────────

  Future<void> _submitOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.isEmpty) {
      setState(() => _errorMessage = '請輸入驗證碼。');
      return;
    }

    setState(() {
      _phase = _Phase.issuing;
      _errorMessage = null;
    });

    try {
      // Issue VC
      final vcJson = await _vcClient.issueCredential(
        did: widget.holderDid,
        email: email,
        otp: otp,
      );
      final vc = VerifiableCredential.fromJson(vcJson);

      // Store VC in wallet
      await _wallet.store(vc);

      // Build and present VP to Relay
      setState(() => _phase = _Phase.presenting);
      final vp = await _vpBuilder.build(
        holderDid: widget.holderDid,
        credentials: [vc],
      );

      final tier = await _relayClient.presentVp(
        holderDid: widget.holderDid,
        vp: vp.toJson(),
      );

      setState(() => _phase = _Phase.done);
      widget.onCredentialAdded(tier);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // On OTP error, go back to waiting for OTP (let user retry)
        _phase = (e is VcIssuerException &&
                (e.error == 'invalid_otp' || e.error == 'expired_otp'))
            ? _Phase.waitingOtp
            : _Phase.idle;
        _errorMessage = _formatError(e);
      });
    }
  }

  // ── Error formatting ───────────────────────────────────────────────────────

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      switch (error.error) {
        case 'invalid_otp':
          return '驗證碼不正確，請重新輸入。';
        case 'expired_otp':
          return '驗證碼已逾期，請重新申請。';
        case 'invalid_email':
          return 'Email 格式無效，請重新輸入。';
        case 'invalid_did':
          return 'DID 格式無效，請重新啟動。';
      }
      if (error.statusCode >= 500) return '發行伺服器暫時無法使用，請稍後再試。';
    }
    if (error is AtProtoException) {
      switch (error.error) {
        case 'invalid_vp':
        case 'invalid_vc':
          return '憑證驗證失敗，請重新嘗試。';
        case 'vc_expired':
          return '憑證已逾期，請重新取得。';
        case 'already_verified':
          return '此帳號已完成驗證。';
      }
      if (error.statusCode >= 500) return 'Relay 暫時無法使用，請稍後再試。';
    }
    return error.toString();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入 Email 憑證')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 64,
                      color: Color(0xFF1A56A4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Email 身份驗證',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '驗證 Email 後可獲得「Verified Human」信任等級',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // Email input
                    TextField(
                      controller: _emailController,
                      enabled: _phase == _Phase.idle,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (_phase == _Phase.idle) _requestOtp();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Email 地址',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // OTP input (shown after requesting)
                    if (_phase == _Phase.waitingOtp ||
                        _phase == _Phase.issuing ||
                        _phase == _Phase.presenting) ...[
                      TextField(
                        controller: _otpController,
                        enabled: _phase == _Phase.waitingOtp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (_phase == _Phase.waitingOtp) _submitOtp();
                        },
                        decoration: const InputDecoration(
                          labelText: '6 位數驗證碼',
                          prefixIcon: Icon(Icons.pin_outlined),
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Phase indicator
                    _buildPhaseIndicator(),
                    const SizedBox(height: 24),

                    // Error message
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade800),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Action button
                    _buildActionButton(),

                    const SizedBox(height: 16),
                    Text(
                      'Email 地址不會上傳至伺服器記錄\n憑證加密存於裝置本地',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
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

  Widget _buildActionButton() {
    final bool busy = _phase != _Phase.idle && _phase != _Phase.waitingOtp;

    if (_phase == _Phase.idle) {
      return FilledButton.icon(
        onPressed: _requestOtp,
        icon: const Icon(Icons.send),
        label: const Text('發送驗證碼'),
      );
    }

    if (_phase == _Phase.waitingOtp) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _submitOtp,
            icon: const Icon(Icons.check),
            label: const Text('驗證並取得憑證'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _phase = _Phase.idle;
              _otpController.clear();
              _errorMessage = null;
            }),
            child: const Text('重新發送驗證碼'),
          ),
        ],
      );
    }

    if (_phase == _Phase.done) {
      return FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.check_circle),
        label: const Text('憑證已加入'),
      );
    }

    return FilledButton(
      onPressed: null,
      child: busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('請稍候…'),
    );
  }

  Widget _buildPhaseIndicator() {
    if (_phase == _Phase.idle) return const SizedBox.shrink();

    final steps = [
      (label: '📧 發送驗證碼', phase: _Phase.requesting),
      (label: '🔢 輸入驗證碼', phase: _Phase.waitingOtp),
      (label: '📜 取得憑證', phase: _Phase.issuing),
      (label: '☁️ 提交 Relay', phase: _Phase.presenting),
      (label: '✅ 信任等級升級', phase: _Phase.done),
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
