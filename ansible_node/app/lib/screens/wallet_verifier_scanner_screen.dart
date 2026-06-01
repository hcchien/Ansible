import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/oid4vp_presentation_service.dart';
import '../services/oid4vp_request.dart';
import '../widgets/elix_focus_route.dart';
import 'wallet_verifier_consent_screen.dart';

class WalletVerifierScannerScreen extends StatefulWidget {
  const WalletVerifierScannerScreen({
    super.key,
    required this.holderDid,
    required this.walletRepository,
    this.presentationService,
    this.onRequestScanned,
    this.allowLocalHttp,
  });

  final String holderDid;
  final WalletRepository walletRepository;
  final Oid4vpPresentationApprover? presentationService;
  final ValueChanged<Oid4vpAuthorizationRequest>? onRequestScanned;
  final bool? allowLocalHttp;

  @override
  State<WalletVerifierScannerScreen> createState() =>
      _WalletVerifierScannerScreenState();
}

class _WalletVerifierScannerScreenState
    extends State<WalletVerifierScannerScreen> {
  bool _handled = false;
  String? _errorMessage;

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) return;
    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (rawValue == null || rawValue.isEmpty) return;

    try {
      final request = Oid4vpAuthorizationRequest.parse(
        rawValue,
        allowLocalHttp: widget.allowLocalHttp ?? !AppEnvironment.isProduction,
      );
      _handled = true;
      widget.onRequestScanned?.call(request);
      Navigator.of(context)
          .push(
            elixFocusPageRoute<void>(
              settings: const RouteSettings(name: '/wallet/verifier-consent'),
              builder: (_) => WalletVerifierConsentScreen(
                holderDid: widget.holderDid,
                request: request,
                presentationService:
                    widget.presentationService ??
                    Oid4vpPresentationService.forWallet(
                      walletRepository: widget.walletRepository,
                    ),
              ),
            ),
          )
          .whenComplete(() {
            if (!mounted) return;
            setState(() => _handled = false);
          });
    } catch (error) {
      setState(() => _errorMessage = _formatError(error));
    }
  }

  String _formatError(Object error) {
    if (error is Oid4vpRequestException) {
      switch (error.code) {
        case 'unsupported_request_scheme':
        case 'insecure_response_uri':
          return context.uiCopy(
            zh: 'QR request 來源不被接受。',
            en: 'This QR request source is not accepted.',
          );
        case 'unsupported_credential_type':
          return context.uiCopy(
            zh: '這個 Verifier 要求 Wallet 不支援的憑證。',
            en: 'This verifier requested a credential Wallet does not support.',
          );
        case 'request_uri_not_supported':
          return context.uiCopy(
            zh: '這個 QR request 格式目前尚未支援。',
            en: 'This QR request format is not supported yet.',
          );
      }
    }
    return context.uiCopy(
      zh: '無法解析這個 QR request。',
      en: 'Could not parse this QR request.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.uiCopy(zh: '掃描驗證請求', en: 'Scan Verification Request'),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(onDetect: _handleCapture),
          Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  context.uiCopy(
                    zh: '掃描 Verifier 顯示的 OID4VP QR',
                    en: 'Scan the OID4VP QR shown by the Verifier',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
          if (_errorMessage != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
