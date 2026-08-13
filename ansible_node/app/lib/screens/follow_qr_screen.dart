import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/follow_qr_link.dart';
import '../services/handle_resolver.dart';

class FollowQrScreen extends StatelessWidget {
  const FollowQrScreen({
    super.key,
    required this.db,
    required this.localDid,
    this.onFollowCreated,
  });

  final AppDatabase db;
  final String localDid;
  final Future<void> Function()? onFollowCreated;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Follow QR Code')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text(
            'Show this code to let someone follow your public identity.',
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: QrImageView(
              data: FollowQrLink(localDid).encode(),
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(shortenDid(localDid)),
          const Spacer(),
          FilledButton.icon(
            key: const Key('scan_follow_qr'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _FollowQrScanner(
                  db: db,
                  localDid: localDid,
                  onFollowCreated: onFollowCreated,
                ),
              ),
            ),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan someone’s QR code'),
          ),
        ],
      ),
    ),
  );
}

class _FollowQrScanner extends StatefulWidget {
  const _FollowQrScanner({
    required this.db,
    required this.localDid,
    this.onFollowCreated,
  });
  final AppDatabase db;
  final String localDid;
  final Future<void> Function()? onFollowCreated;
  @override
  State<_FollowQrScanner> createState() => _FollowQrScannerState();
}

class _FollowQrScannerState extends State<_FollowQrScanner> {
  bool _handled = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) return;
    try {
      final target = FollowQrLink.parse(raw).did;
      if (target == widget.localDid) throw const FormatException('self_follow');
      _handled = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Follow this person?'),
          content: Text(
            'You are about to follow ${shortenDid(target)}. This shares your follow action with your selected sync services.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Follow'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        _handled = false;
        return;
      }
      final service = FollowService(
        followRepository: DriftFollowRepository(widget.db),
        outboxRepository: DriftFollowActivityOutboxRepository(widget.db),
        boardSyncConfigRepository: DriftBoardSyncConfigRepository(widget.db),
        postRepository: DriftPostRepository(widget.db),
        contentItemRepository: DriftContentItemRepository(widget.db),
      );
      await service.followUser(
        followerDid: widget.localDid,
        targetDid: target,
        displayName: shortenDid(target),
        now: DateTime.now().toUtc(),
      );
      await widget.onFollowCreated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Following added')));
      Navigator.of(context).pop();
    } on FormatException {
      if (mounted) {
        setState(() => _error = 'This is not a valid Follow QR code.');
      }
      _handled = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan Follow QR Code')),
    body: Stack(
      children: [
        MobileScanner(onDetect: _onDetect),
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
