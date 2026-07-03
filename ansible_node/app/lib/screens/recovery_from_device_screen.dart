import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/atproto_client.dart';
import '../services/recovery_approval_service.dart';
import '../services/relay_anchor_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// NEW-device half of approve-from-other-device recovery (design flow 3a):
/// the user has no backup but still holds an old, enrolled device. This
/// screen resolves their handle, generates a fresh identity + device key,
/// and shows the signed recovery request as a QR for the old device to
/// scan and approve. It then polls until the relay holds the re-anchor in
/// its grace window.
class RecoveryFromDeviceScreen extends StatefulWidget {
  const RecoveryFromDeviceScreen({
    super.key,
    required this.installRecoveredKey,
    this.service,
    this.handleResolver,
  });

  /// Persists the NEW identity private key (hex) into secure storage once
  /// the request is approved (pending) — the key becomes usable when the
  /// grace window promotes the anchor. Same seam the recovery wizard uses.
  final Future<void> Function(String privateKeyHex) installRecoveredKey;

  /// Injectable for tests; defaults to the relay from the build config.
  final RecoveryApprovalService? service;

  /// handle → DID. Defaults to the relay's resolveHandle XRPC.
  final Future<String> Function(String handle)? handleResolver;

  @override
  State<RecoveryFromDeviceScreen> createState() =>
      _RecoveryFromDeviceScreenState();
}

class _RecoveryFromDeviceScreenState extends State<RecoveryFromDeviceScreen> {
  final _handleController = TextEditingController();
  RecoveryApprovalRequest? _request;
  String? _did;
  bool _busy = false;
  bool _approved = false;
  String? _error;
  Timer? _poll;

  RecoveryApprovalService get _service =>
      widget.service ??
      RecoveryApprovalService(
        relayClient: RelayAnchorClient(
          baseUrl: AppEnvironment.defaultRelayBaseUrl,
        ),
      );

  @override
  void dispose() {
    _poll?.cancel();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) return;
    final notFoundMessage = context.uiCopy(
      zh: '找不到這個 handle 的身分',
      en: 'No identity found for that handle',
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final resolve = widget.handleResolver ??
          (h) => AtProtoClient(
                baseUrl: AppEnvironment.defaultRelayBaseUrl,
              ).resolveHandle(h);
      final did = await resolve(handle);
      final request = await _service.buildRequest(did: did, handle: handle);
      if (!mounted) return;
      if (request == null) {
        setState(() {
          _busy = false;
          _error = notFoundMessage;
        });
        return;
      }
      setState(() {
        _did = did;
        _request = request;
        _busy = false;
      });
      _startPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = notFoundMessage;
      });
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      final did = _did;
      final request = _request;
      if (did == null || request == null || _approved) return;
      final pending = await _service.pendingFor(did);
      if (!mounted || pending == null) return;
      if (pending.anchorCid == request.anchor.computeCid()) {
        _poll?.cancel();
        await widget.installRecoveredKey(request.identitySeedHex);
        if (!mounted) return;
        setState(() => _approved = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '用另一台裝置核可', en: 'APPROVE FROM DEVICE'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
        children: [
          if (_request == null) ..._buildInputStep() else ..._buildQrStep(),
        ],
      ),
    );
  }

  List<Widget> _buildInputStep() {
    return [
      Text(
        context.uiCopy(
          zh: '沒有備份也沒關係 — 只要你的舊裝置還在。輸入你的 handle，'
              '用舊裝置掃描下一步出現的 QR 即可核可這台新裝置。',
          en: 'No backup needed — as long as your old device survives. Enter '
              'your handle, then scan the QR on the next step with the old '
              'device to approve this one.',
        ),
        style: const TextStyle(
          fontFamily: AnsibleDesign.serif,
          fontSize: 14.5,
          height: 1.7,
          color: AnsibleDesign.inkMuted,
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('recovery_from_device_handle'),
        controller: _handleController,
        autofocus: true,
        decoration: InputDecoration(
          labelText: context.uiCopy(zh: '你的 handle', en: 'Your handle'),
          hintText: 'tris.elix.cool',
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('recovery_from_device_build'),
        onPressed: _busy ? null : _build,
        child: Text(
          _busy
              ? context.uiCopy(zh: '準備中…', en: 'Preparing…')
              : context.uiCopy(zh: '產生核可 QR', en: 'Generate approval QR'),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          key: const Key('recovery_from_device_error'),
          style: const TextStyle(fontSize: 13, color: AnsibleDesign.ember),
        ),
      ],
    ];
  }

  List<Widget> _buildQrStep() {
    final request = _request!;
    if (_approved) {
      return [
        const Icon(Icons.verified_outlined,
            size: 44, color: AnsibleDesign.spore),
        const SizedBox(height: 14),
        Text(
          context.uiCopy(zh: '已核可', en: 'Approved'),
          key: const Key('recovery_from_device_approved'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: AnsibleDesign.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.uiCopy(
            zh: '為了防止劫持，復原會有 72 小時的寬限期 — 期間你其他的裝置都'
                '可以否決。寬限期過後，這台裝置就能用你的身分發文。',
            en: 'To resist hijacking, recovery waits out a 72-hour grace '
                'window during which your other devices can veto. After '
                'that, this device posts as you.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 14,
            height: 1.7,
            color: AnsibleDesign.inkMuted,
          ),
        ),
      ];
    }
    return [
      Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AnsibleDesign.rule, width: 0.5),
          ),
          child: QrImageView(
            data: request.toQrPayload(),
            version: QrVersions.auto,
            size: 260,
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        context.uiCopy(
          zh: '用舊裝置開啟 設定 → 核可另一台裝置的復原，掃描這個 QR。',
          en: 'On the old device open Settings → Approve a device recovery '
              'and scan this QR.',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: AnsibleDesign.serif,
          fontSize: 14,
          height: 1.65,
          color: AnsibleDesign.inkMuted,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        context.uiCopy(
          zh: '金鑰指紋（兩台裝置應一致）\n${request.newKeyFingerprint}',
          en: 'Key fingerprint (must match on both devices)\n'
              '${request.newKeyFingerprint}',
        ),
        key: const Key('recovery_from_device_fingerprint'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 11,
          height: 1.8,
          color: AnsibleDesign.inkFaint,
        ),
      ),
      const SizedBox(height: 12),
      const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ];
  }
}
