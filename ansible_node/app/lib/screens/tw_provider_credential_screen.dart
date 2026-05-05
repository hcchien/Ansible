import 'dart:async';
import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:ansible_vc/ansible_vc.dart';
import 'package:flutter/material.dart';

import '../services/external_url_launcher.dart';
import '../services/vc_issuer_client.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('TW 身份驗證')),
      body: TwProviderCredentialPanel(
        holderDid: holderDid,
        vcIssuerClient: vcIssuerClient,
        urlLauncher: urlLauncher,
        walletRepository: walletRepository,
        pollInterval: pollInterval,
        pollTimeout: pollTimeout,
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
    _walletRepository = widget.walletRepository ?? InMemoryWalletRepository();
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
      setState(() => _errorMessage = '請輸入有效的 Email 地址。');
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
          _errorMessage = '開啟驗證頁失敗';
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
        _errorMessage = '尚未收到驗證結果';
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
    final vc = VerifiableCredential.fromJson(vcJson);
    final now = DateTime.now().toUtc();
    final validFrom = DateTime.parse(vc.issuanceDate).toUtc();
    final validUntil = vc.expirationDate == null
        ? validFrom.add(const Duration(days: 90))
        : DateTime.parse(vc.expirationDate!).toUtc();

    await _walletRepository.saveCredential(
      metadata: WalletCredential(
        credentialId: vc.id,
        issuerDid: vc.issuer,
        holderDid: vc.holderDid ?? widget.holderDid,
        credentialType: vc.type.contains('TrisAuraHumanityCredential')
            ? 'TrisAuraHumanityCredential'
            : vc.type.last,
        status: WalletCredentialStatus.active,
        validFrom: validFrom,
        validUntil: validUntil,
        displayName: 'Verified Human',
        createdAt: now,
        updatedAt: now,
      ),
      encryptedPayload: jsonEncode(vc.toJson()),
      encryptionVersion: 'plain-json-v1',
    );
    widget.onCredentialStored?.call();

    if (!mounted) return;
    setState(() => _phase = _Phase.done);
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      switch (error.error) {
        case 'invalid_email':
          return 'Email 格式無效，請重新輸入。';
        case 'invalid_did':
          return 'DID 格式無效，請重新啟動。';
        case 'callback_replay':
        case 'state_mismatch':
        case 'invalid_provider_proof':
          return '驗證安全檢查失敗，請重新開始。';
        case 'provider_not_verified':
          return '等待 provider 驗證完成';
      }
      if (error.statusCode >= 500) {
        return '發行伺服器暫時無法使用，請稍後再試。';
      }
    }
    return '發行流程暫時無法完成，請稍後再試。';
  }

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
      setState(() => _errorMessage = '開啟驗證頁失敗');
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
        _errorMessage = '尚未收到驗證結果';
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
                  color: Color(0xFFFF9F43),
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
                    decoration: const InputDecoration(
                      labelText: 'Email 地址',
                      prefixIcon: Icon(Icons.email_outlined),
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
                    label: const Text('開始驗證'),
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
                      if (_offer != null && _errorMessage == '開啟驗證頁失敗')
                        FilledButton.icon(
                          onPressed: _retryLaunch,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('重新開啟驗證頁'),
                        ),
                      if (_offer != null)
                        OutlinedButton.icon(
                          onPressed: _checkAgain,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重新檢查'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('重新開始'),
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
        return 'TW 身份驗證';
      case _Phase.polling:
        return '等待 provider 驗證完成';
      case _Phase.issuing:
        return '正在發行憑證';
      case _Phase.done:
        return '憑證已加入 Wallet';
      case _Phase.error:
        return '驗證流程暫停';
    }
  }

  String get _body {
    switch (_phase) {
      case _Phase.idle:
        return '輸入 Email 後，系統會開啟 TW provider 驗證頁。';
      case _Phase.starting:
        return '正在建立驗證工作階段。';
      case _Phase.polling:
        return '完成瀏覽器中的驗證後，請回到 App 等候憑證發行。';
      case _Phase.issuing:
        return 'Issuer 已確認驗證結果，正在建立你的 humanity credential。';
      case _Phase.done:
        return '你可以回到 Wallet 查看憑證狀態。';
      case _Phase.error:
        return '你可以稍後重試，或重新開始驗證流程。';
    }
  }
}
