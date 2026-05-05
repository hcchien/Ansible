import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../services/external_url_launcher.dart';
import '../services/vc_issuer_client.dart';

enum _Phase { idle, starting, polling, error }

class TwProviderCredentialScreen extends StatefulWidget {
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
  State<TwProviderCredentialScreen> createState() =>
      _TwProviderCredentialScreenState();
}

class _TwProviderCredentialScreenState
    extends State<TwProviderCredentialScreen> {
  final _emailController = TextEditingController();

  late final VcIssuerClient _vcIssuerClient;
  late final ExternalUrlLauncher _urlLauncher;

  _Phase _phase = _Phase.idle;
  String? _errorMessage;
  TwProviderOffer? _offer;

  @override
  void initState() {
    super.initState();
    _vcIssuerClient = widget.vcIssuerClient ?? VcIssuerClient();
    _urlLauncher = widget.urlLauncher ?? const UrlLauncherExternalUrlLauncher();
  }

  @override
  void dispose() {
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMessage = _formatError(error);
      });
    }
  }

  String _formatError(Object error) {
    if (error is VcIssuerException) {
      switch (error.error) {
        case 'invalid_email':
          return 'Email 格式無效，請重新輸入。';
        case 'invalid_did':
          return 'DID 格式無效，請重新啟動。';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TW 身份驗證')),
      body: SafeArea(
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
                ],
              ),
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
      case _Phase.error:
        return '你可以稍後重試，或重新開始驗證流程。';
    }
  }
}
