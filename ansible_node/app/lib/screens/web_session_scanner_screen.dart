import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/web_session_grant_service.dart';
import 'web_session_approval_screen.dart';

class WebSessionScannerScreen extends StatefulWidget {
  final String currentDid;
  final ValueChanged<WebSessionApprovalLink>? onLinkScanned;

  const WebSessionScannerScreen({
    super.key,
    required this.currentDid,
    this.onLinkScanned,
  });

  @override
  State<WebSessionScannerScreen> createState() =>
      _WebSessionScannerScreenState();
}

class _WebSessionScannerScreenState extends State<WebSessionScannerScreen> {
  bool _handled = false;
  String? _error;

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) return;
    String? rawValue;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        rawValue = barcode.rawValue;
        break;
      }
    }
    if (rawValue == null) return;

    try {
      final link = WebSessionApprovalLink.parse(Uri.parse(rawValue));
      _handled = true;
      widget.onLinkScanned?.call(link);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WebSessionApprovalScreen(
            challengeId: link.challengeId,
            currentDid: widget.currentDid,
          ),
        ),
      );
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan web session')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _handleCapture),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
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
