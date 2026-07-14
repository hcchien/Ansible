import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/recovery_approval_service.dart';
import '../services/relay_anchor_client.dart';
import '../services/web_session_approval_client.dart';
import '../services/web_session_grant_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/elix_focus_route.dart';
import 'web_session_approval_screen.dart';

typedef RecoveryQrScannerBuilder =
    Widget Function(
      BuildContext context,
      ValueChanged<BarcodeCapture> onDetect,
    );

typedef RecoveryWebSessionApprovalRouteBuilder =
    Widget Function(BuildContext context, WebSessionApprovalLink link);

/// OLD-device half of approve-from-other-device recovery: scan the new
/// device's QR, show the user WHAT they are approving (whose identity, the
/// new key fingerprint), and on confirmation sign the recovery proof with
/// this device's enrolled device key and submit. The relay still holds the
/// re-anchor in the 72h grace window (other devices are alerted and can
/// veto).
class RecoveryApproveScannerScreen extends StatefulWidget {
  const RecoveryApproveScannerScreen({
    super.key,
    required this.localDid,
    this.service,
    this.allowLocalHttp,
    this.allowedWebSessionRelayOrigins,
    this.scannerBuilder,
    this.webSessionApprovalBuilder,
  });

  final String localDid;

  /// Injectable for tests; defaults to the relay from the build config.
  final RecoveryApprovalService? service;
  final bool? allowLocalHttp;
  final Set<String>? allowedWebSessionRelayOrigins;
  final RecoveryQrScannerBuilder? scannerBuilder;
  final RecoveryWebSessionApprovalRouteBuilder? webSessionApprovalBuilder;

  @override
  State<RecoveryApproveScannerScreen> createState() =>
      _RecoveryApproveScannerScreenState();
}

class _RecoveryApproveScannerScreenState
    extends State<RecoveryApproveScannerScreen> {
  bool _handling = false;
  String? _errorMessage;

  RecoveryApprovalService get _service =>
      widget.service ??
      RecoveryApprovalService(
        relayClient: RelayAnchorClient(
          baseUrl: AppEnvironment.defaultRelayBaseUrl,
        ),
      );

  Future<void> _handleCapture(BarcodeCapture capture) async {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    await _handleRaw(raw, manual: false);
  }

  /// Shared routing for a request payload, whether scanned or pasted.
  /// Scanning ignores payloads it does not recognize (keep scanning);
  /// manual entry surfaces an error instead — the user expects feedback.
  Future<void> _handleRaw(String raw, {required bool manual}) async {
    if (_handling) return;
    if (_handleWebSessionCapture(raw)) return;
    final anchor = RecoveryApprovalService.parseRequest(raw);
    if (anchor == null) {
      if (manual && mounted) {
        setState(
          () => _errorMessage = context.uiCopy(
            zh: '無法解析貼上的內容，請確認複製了完整的請求內容。',
            en: 'Could not parse the pasted content — make sure the full '
                'request was copied.',
          ),
        );
      }
      return; // not our QR — keep scanning
    }
    _handling = true;
    try {
      await _confirmAndApprove(anchor);
    } finally {
      if (mounted) _handling = false;
    }
  }

  /// No-camera fallback (desktops without a webcam, or camera permission
  /// denied): paste the request payload the new device copied.
  Future<void> _openManualEntry() async {
    final submitted = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualEntryDialog(),
    );
    if (submitted == null || submitted.isEmpty || !mounted) return;
    setState(() => _errorMessage = null);
    await _handleRaw(submitted, manual: true);
  }

  bool _handleWebSessionCapture(String rawValue) {
    final uri = Uri.tryParse(rawValue);
    final isWebSessionLink =
        uri?.scheme == 'trisaura' &&
        uri?.host == 'web-session' &&
        uri?.path == '/approve';
    if (!isWebSessionLink) return false;

    try {
      final link = WebSessionApprovalLink.parse(
        uri!,
        allowedRelayOrigins:
            widget.allowedWebSessionRelayOrigins ??
            const {AppEnvironment.defaultRelayBaseUrl},
        allowLocalHttp: widget.allowLocalHttp ?? !AppEnvironment.isProduction,
      );
      _handling = true;
      setState(() => _errorMessage = null);
      Navigator.of(context)
          .push<bool>(
            elixFocusPageRoute<bool>(
              settings: const RouteSettings(name: '/web-session/approve'),
              builder: (routeContext) =>
                  widget.webSessionApprovalBuilder?.call(routeContext, link) ??
                  WebSessionApprovalScreen(
                    challengeId: link.challengeId,
                    currentDid: widget.localDid,
                    client: WebSessionApprovalClient(baseUrl: link.relayOrigin),
                  ),
            ),
          )
          .then((approved) {
            if (!mounted) return;
            if (approved == true && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            _handling = false;
          });
    } catch (_) {
      setState(
        () => _errorMessage = context.uiCopy(
          zh: '無法解析這個 QR request。',
          en: 'Could not parse this QR request.',
        ),
      );
    }

    return true;
  }

  Future<void> _confirmAndApprove(dynamic anchor) async {
    final fingerprint = _fingerprint(anchor.identityKey as String);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          context.uiCopy(zh: '核可這台新裝置？', en: 'Approve this new device?'),
          style: const TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.uiCopy(
                zh:
                    '這會讓一台新裝置在 72 小時寬限期後接管你的身分'
                    '（${anchor.handle}）。只在你自己正在復原時核可。',
                en:
                    'A new device will take over your identity '
                    '(${anchor.handle}) after the 72h grace window. Approve '
                    'only if YOU are recovering right now.',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 14.5,
                height: 1.65,
                color: AnsibleDesign.inkMuted,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.uiCopy(
                zh: '金鑰指紋（需與新裝置畫面一致）\n$fingerprint',
                en: 'Key fingerprint (must match the new device)\n$fingerprint',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                height: 1.8,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            key: const Key('recovery_approve_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.uiCopy(zh: '核可', en: 'Approve')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final doneMessage = context.uiCopy(
      zh: '已送出核可。寬限期後新裝置生效；期間其他裝置可否決。',
      en:
          'Approval submitted. The new device activates after the grace '
          'window; other devices can veto until then.',
    );
    final staleMessage = context.uiCopy(
      zh: '這個請求已過期，請在新裝置上重新產生 QR',
      en: 'This request is stale — regenerate the QR on the new device',
    );
    final failedMessage = context.uiCopy(
      zh: '核可失敗，請確認網路後再試',
      en: 'Approval failed — check the network and retry',
    );

    try {
      await _service.approve(localDid: widget.localDid, anchor: anchor);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(doneMessage)));
    } on RecoveryApprovalException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            error.reason == 'stale_request' ? staleMessage : failedMessage,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(failedMessage)));
    }
  }

  static String _fingerprint(String hex) {
    return hex.length >= 16
        ? '${hex.substring(0, 8)}…${hex.substring(hex.length - 8)}'
        : hex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.uiCopy(zh: '核可另一台裝置的復原', en: 'Approve a device recovery'),
        ),
      ),
      body: Stack(
        children: [
          (widget.scannerBuilder ?? _defaultScannerBuilder)(
            context,
            _handleCapture,
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  context.uiCopy(
                    zh: '掃描新裝置畫面上的復原 QR，或網頁登入 QR',
                    en: 'Scan a device recovery QR or web login QR',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: _errorMessage != null ? 64 : 16,
              ),
              child: TextButton(
                key: const Key('recovery_manual_entry_button'),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                onPressed: _openManualEntry,
                child: Text(
                  context.uiCopy(
                    zh: '無法使用相機？手動貼上請求內容',
                    en: "Can't use the camera? Paste the request",
                  ),
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

Widget _defaultScannerBuilder(
  BuildContext context,
  ValueChanged<BarcodeCapture> onDetect,
) {
  return MobileScanner(onDetect: onDetect);
}

/// Paste-the-request dialog. Owns its own controller so it is disposed with
/// the dialog's State (not before the exit transition, which is what a
/// controller disposed inline after showDialog would hit).
class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog();

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        context.uiCopy(zh: '貼上請求內容', en: 'Paste the request'),
        style: const TextStyle(
          fontFamily: AnsibleDesign.serif,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.uiCopy(
              zh: '在新裝置的 QR 畫面點「複製請求內容」，把內容傳給這台裝置後貼上。',
              en: 'On the new device tap "Copy request" below the QR, '
                  'transfer it to this device, and paste it here.',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 13.5,
              height: 1.6,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('recovery_manual_entry_field'),
            controller: _controller,
            maxLines: 5,
            autofocus: true,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11,
            ),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          key: const Key('recovery_manual_entry_submit'),
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: Text(context.uiCopy(zh: '繼續', en: 'Continue')),
        ),
      ],
    );
  }
}
