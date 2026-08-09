import 'dart:async';
import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/credential_payload_codec.dart';
import '../services/external_url_launcher.dart';
import '../services/vc_issuer_client.dart';
import '../theme/ansible_design.dart';

enum _Phase { idle, starting, polling, issuing, done, error }

class TwProviderCredentialScreen extends StatelessWidget {
  const TwProviderCredentialScreen({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.urlLauncher,
    this.walletRepository,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 2),
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final WalletRepository? walletRepository;
  final Duration pollInterval;
  final Duration pollTimeout;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AnsibleDesign.theme(),
      child: Scaffold(
        backgroundColor: AnsibleDesign.paper,
        appBar: AppBar(
          title: Text(
            context.uiCopy(zh: 'TW 身份驗證', en: 'TW Identity Verification'),
          ),
        ),
        body: TwProviderCredentialPanel(
          holderDid: holderDid,
          vcIssuerClient: vcIssuerClient,
          urlLauncher: urlLauncher,
          walletRepository: walletRepository,
          pollInterval: pollInterval,
          pollTimeout: pollTimeout,
        ),
      ),
    );
  }
}

class TwProviderCredentialPanel extends StatefulWidget {
  const TwProviderCredentialPanel({
    super.key,
    required this.holderDid,
    this.vcIssuerClient,
    this.urlLauncher,
    this.walletRepository,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 2),
    this.onCredentialStored,
  });

  final String holderDid;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final WalletRepository? walletRepository;
  final Duration pollInterval;
  final Duration pollTimeout;
  final VoidCallback? onCredentialStored;

  @override
  State<TwProviderCredentialPanel> createState() =>
      _TwProviderCredentialPanelState();
}

class _TwProviderCredentialPanelState extends State<TwProviderCredentialPanel> {
  final _emailController = TextEditingController();

  late final VcIssuerClient _vcIssuerClient;
  late final ExternalUrlLauncher _urlLauncher;
  late final WalletRepository _walletRepository;

  _Phase _phase = _Phase.idle;
  String? _errorMessage;
  TwProviderOffer? _offer;
  Timer? _pollTimer;
  Timer? _pollTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _vcIssuerClient = widget.vcIssuerClient ?? VcIssuerClient();
    _urlLauncher = widget.urlLauncher ?? const UrlLauncherExternalUrlLauncher();
    final walletRepository = widget.walletRepository;
    if (walletRepository == null) {
      throw StateError('TwProviderCredentialPanel requires a WalletRepository');
    }
    _walletRepository = walletRepository;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _startFlow() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      setState(
        () => _errorMessage = _copy(
          zh: '請輸入有效的 Email 地址。',
          en: 'Enter a valid email address.',
        ),
      );
      return;
    }

    setState(() {
      _phase = _Phase.starting;
      _errorMessage = null;
    });

    try {
      final offer = await _vcIssuerClient.startTwProviderFlow(
        did: widget.holderDid,
        email: email,
      );
      final opened = await _urlLauncher.open(offer.authorizationUrl);
      if (!opened) {
        if (!mounted) return;
        setState(() {
          _offer = offer;
          _phase = _Phase.error;
          _errorMessage = _openVerificationPageFailed;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _phase = _Phase.polling;
      });
      _beginPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  void _beginPolling() {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    _pollOnce();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _pollOnce());
    _pollTimeoutTimer = Timer(widget.pollTimeout, () {
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _copy(
          zh: '尚未收到驗證結果',
          en: 'Verification result has not arrived yet',
        );
      });
    });
  }

  Future<void> _pollOnce() async {
    final offer = _offer;
    if (offer == null || _phase != _Phase.polling) return;

    try {
      final status = await _vcIssuerClient.getTwProviderStatus(offer.offerId);
      if (!status.isVerified) return;
      await _issueAndStore(offer.offerId);
    } catch (error) {
      if (!mounted) return;
      if (error is VcIssuerException &&
          error.error == 'provider_not_verified') {
        setState(() {
          _phase = _Phase.polling;
          _errorMessage = null;
        });
        return;
      }
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  Future<void> _issueAndStore(String offerId) async {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.issuing;
      _errorMessage = null;
    });

    final vcJson = await _vcIssuerClient.issueTwProviderCredential(
      did: widget.holderDid,
      email: _emailController.text.trim(),
      offerId: offerId,
    );
    final credential = TrisAuraCredential.fromJson(
      Map<String, Object?>.from(vcJson),
    );
    final now = DateTime.now().toUtc();

    final payloadEnvelope = await const SecureCredentialPayloadCodec().seal(
      credentialId: credential.id,
      payloadJson: jsonEncode(credential.json),
    );

    await _walletRepository.saveCredential(
      metadata: WalletCredential(
        credentialId: credential.id,
        issuerDid: credential.issuerDid,
        holderDid: credential.holderDid,
        credentialType: credential.types.contains('TrisAuraHumanityCredential')
            ? 'TrisAuraHumanityCredential'
            : credential.types.last,
        status: WalletCredentialStatus.active,
        validFrom: credential.validFrom,
        validUntil: credential.validUntil,
        displayName: 'Verified Human',
        createdAt: now,
        updatedAt: now,
      ),
      encryptedPayload: payloadEnvelope.encodedPayload,
      encryptionVersion: payloadEnvelope.encryptionVersion,
    );
    widget.onCredentialStored?.call();

    if (!mounted) return;
    setState(() => _phase = _Phase.done);
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      switch (error.error) {
        case 'invalid_email':
          return _copy(
            zh: 'Email 格式無效，請重新輸入。',
            en: 'Invalid email format. Enter it again.',
          );
        case 'invalid_did':
          return _copy(
            zh: 'DID 格式無效，請重新啟動。',
            en: 'Invalid DID format. Restart the flow.',
          );
        case 'callback_replay':
        case 'state_mismatch':
        case 'invalid_provider_proof':
          return _copy(
            zh: '驗證安全檢查失敗，請重新開始。',
            en: 'Verification security check failed. Start again.',
          );
        case 'provider_not_verified':
          return _copy(
            zh: '等待 provider 驗證完成',
            en: 'Waiting for provider verification',
          );
      }
      if (error.statusCode >= 500) {
        return _copy(
          zh: '發行伺服器暫時無法使用，請稍後再試。',
          en: 'Issuer is temporarily unavailable. Try again later.',
        );
      }
    }
    return _copy(
      zh: '發行流程暫時無法完成，請稍後再試。',
      en: 'Issuance cannot be completed right now. Try again later.',
    );
  }

  String _copy({required String zh, required String en}) {
    return context.uiCopy(zh: zh, en: en);
  }

  String get _openVerificationPageFailed =>
      _copy(zh: '開啟驗證頁失敗', en: 'Could not open verification page');

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _isBusy => _phase == _Phase.starting;

  Future<void> _retryLaunch() async {
    final offer = _offer;
    if (offer == null) return;
    final opened = await _urlLauncher.open(offer.authorizationUrl);
    if (!mounted) return;
    if (opened) {
      setState(() {
        _phase = _Phase.polling;
        _errorMessage = null;
      });
      _beginPolling();
    } else {
      setState(() => _errorMessage = _openVerificationPageFailed);
    }
  }

  Future<void> _checkAgain() async {
    final offer = _offer;
    if (offer == null) return;
    setState(() {
      _phase = _Phase.polling;
      _errorMessage = null;
    });
    try {
      final status = await _vcIssuerClient.getTwProviderStatus(offer.offerId);
      if (status.isVerified) {
        await _issueAndStore(offer.offerId);
        return;
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _copy(
          zh: '尚未收到驗證結果',
          en: 'Verification result has not arrived yet',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  void _restart() {
    _pollTimer?.cancel();
    _pollTimeoutTimer?.cancel();
    setState(() {
      _phase = _Phase.idle;
      _offer = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 56,
                  color: Color(0xFFFFB26B),
                ),
                const SizedBox(height: 16),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_phase == _Phase.idle || _phase == _Phase.starting) ...[
                  TextField(
                    controller: _emailController,
                    enabled: !_isBusy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: _copy(zh: 'Email 地址', en: 'Email address'),
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _startFlow,
                    icon: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.open_in_new),
                    label: Text(_copy(zh: '開始驗證', en: 'Start verification')),
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF6B6B)),
                  ),
                ],
                if (_offer != null && _phase == _Phase.polling) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                ],
                if (_phase == _Phase.error) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (_offer != null &&
                          _errorMessage == _openVerificationPageFailed)
                        FilledButton.icon(
                          onPressed: _retryLaunch,
                          icon: const Icon(Icons.open_in_new),
                          label: Text(
                            _copy(
                              zh: '重新開啟驗證頁',
                              en: 'Reopen verification page',
                            ),
                          ),
                        ),
                      if (_offer != null)
                        OutlinedButton.icon(
                          onPressed: _checkAgain,
                          icon: const Icon(Icons.refresh),
                          label: Text(_copy(zh: '重新檢查', en: 'Check again')),
                        ),
                      OutlinedButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(_copy(zh: '重新開始', en: 'Restart')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (_phase) {
      case _Phase.idle:
      case _Phase.starting:
        return _copy(zh: 'TW 身份驗證', en: 'TW Identity Verification');
      case _Phase.polling:
        return _copy(
          zh: '等待 provider 驗證完成',
          en: 'Waiting for provider verification',
        );
      case _Phase.issuing:
        return _copy(zh: '正在發行憑證', en: 'Issuing credential');
      case _Phase.done:
        return _copy(zh: '憑證已加入 Wallet', en: 'Credential added to Wallet');
      case _Phase.error:
        return _copy(zh: '驗證流程暫停', en: 'Verification paused');
    }
  }

  String get _body {
    switch (_phase) {
      case _Phase.idle:
        return _copy(
          zh: '輸入 Email 後，系統會開啟 TW provider 驗證頁。',
          en: 'Enter your email and the app will open the TW provider verification page.',
        );
      case _Phase.starting:
        return _copy(zh: '正在建立驗證工作階段。', en: 'Creating a verification session.');
      case _Phase.polling:
        return _copy(
          zh: '完成瀏覽器中的驗證後，請回到 App 等候憑證發行。',
          en: 'After completing browser verification, return to the app and wait for issuance.',
        );
      case _Phase.issuing:
        return _copy(
          zh: 'Issuer 已確認驗證結果，正在建立你的 humanity credential。',
          en: 'Issuer confirmed the verification result and is creating your humanity credential.',
        );
      case _Phase.done:
        return _copy(
          zh: '你可以回到 Wallet 查看憑證狀態。',
          en: 'You can return to Wallet to view credential status.',
        );
      case _Phase.error:
        return _copy(
          zh: '你可以稍後重試，或重新開始驗證流程。',
          en: 'Try again later or restart verification.',
        );
    }
  }
}
