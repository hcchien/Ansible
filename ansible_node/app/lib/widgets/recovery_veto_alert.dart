import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/recovery_veto_service.dart';
import '../services/relay_anchor_client.dart';
import '../theme/ansible_design.dart';

/// Veto alert (recovery design §hijack resistance): shown when a `recovery`
/// re-anchor for this DID is sitting in its grace window. One tap signs a
/// veto with this device's identity key and freezes the account; ignoring is
/// legitimate when the user started the recovery themselves on another
/// device.
Future<void> showRecoveryVetoAlert(
  BuildContext context, {
  required String did,
  required PendingAnchor pending,
  required RecoveryVetoService vetoService,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _RecoveryVetoDialog(
      did: did,
      pending: pending,
      vetoService: vetoService,
    ),
  );
}

class _RecoveryVetoDialog extends StatefulWidget {
  const _RecoveryVetoDialog({
    required this.did,
    required this.pending,
    required this.vetoService,
  });

  final String did;
  final PendingAnchor pending;
  final RecoveryVetoService vetoService;

  @override
  State<_RecoveryVetoDialog> createState() => _RecoveryVetoDialogState();
}

class _RecoveryVetoDialogState extends State<_RecoveryVetoDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _veto() async {
    final failureMessage = context.uiCopy(
      zh: '否決失敗 — 請確認網路後再試',
      en: 'Veto failed — check the network and retry',
    );
    final doneMessage = context.uiCopy(
      zh: '已否決。帳號已凍結，等待人工處理。',
      en: 'Vetoed. The account is frozen pending manual resolution.',
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.vetoService.veto(did: widget.did, pending: widget.pending);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(doneMessage)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failureMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grace = widget.pending.graceUntil?.toLocal();
    return AlertDialog(
      backgroundColor: AnsibleDesign.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(
            Icons.gpp_maybe_outlined,
            color: AnsibleDesign.ember,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.uiCopy(zh: '偵測到帳號復原請求', en: 'Account recovery requested'),
              style: const TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AnsibleDesign.ink,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.uiCopy(
              zh: '有人正在用備份復原這個身分。如果是你自己在另一台裝置上發起的，可以忽略；'
                  '如果不是，請立即否決 — 帳號會被凍結，復原將無法完成。',
              en: 'Someone is recovering this identity from a backup. If you '
                  'started this on another device, you can ignore it; if not, '
                  'veto now — the account freezes and the recovery cannot '
                  'complete.',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 14.5,
              height: 1.65,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          if (grace != null) ...[
            const SizedBox(height: 12),
            Text(
              context.uiCopy(
                zh: '寬限期至 $grace',
                en: 'Grace window ends $grace',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('recovery_veto_error'),
              style: const TextStyle(
                fontSize: 13,
                color: AnsibleDesign.ember,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('recovery_veto_dismiss'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(
            context.uiCopy(zh: '這是我發起的', en: 'This was me'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 14,
              color: AnsibleDesign.inkMuted,
            ),
          ),
        ),
        FilledButton(
          key: const Key('recovery_veto_confirm'),
          onPressed: _busy ? null : _veto,
          style: FilledButton.styleFrom(
            backgroundColor: AnsibleDesign.ember,
            foregroundColor: AnsibleDesign.paper,
          ),
          child: Text(
            _busy
                ? context.uiCopy(zh: '否決中…', en: 'Vetoing…')
                : context.uiCopy(zh: '不是我 — 立即否決', en: 'Not me — veto now'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
