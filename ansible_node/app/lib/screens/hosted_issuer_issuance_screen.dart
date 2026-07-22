import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_l10n.dart';
import '../services/hosted_issuer_admin_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class HostedIssuerIssuanceScreen extends StatefulWidget {
  const HostedIssuerIssuanceScreen({
    super.key,
    required this.tenantId,
    required this.client,
  });

  final String tenantId;
  final HostedIssuerAdminClient client;

  @override
  State<HostedIssuerIssuanceScreen> createState() =>
      _HostedIssuerIssuanceScreenState();
}

class _HostedIssuerIssuanceScreenState
    extends State<HostedIssuerIssuanceScreen> {
  final _credentialId = TextEditingController();
  HostedIssuerAdminCapability? _capability;
  List<HostedIssuanceRequest> _requests = const [];
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _credentialId.dispose();
    super.dispose();
  }

  Future<HostedIssuerAdminCapability> _authorize() async {
    final current = _capability;
    if (current != null && current.expiresAt.isAfter(DateTime.now().toUtc())) {
      return current;
    }
    final capability = await widget.client.authenticateAdministrator(
      tenantId: widget.tenantId,
      scopes: const {'issuer_admin:issuance', 'issuer_admin:status'},
    );
    _capability = capability;
    return capability;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() => _run(() async {
    final capability = await _authorize();
    final requests = await widget.client.listIssuanceRequests(
      tenantId: widget.tenantId,
      capability: capability,
    );
    if (mounted) setState(() => _requests = requests);
  });

  Future<void> _decide(
    HostedIssuanceRequest request,
    String decision,
  ) => _run(() async {
    final offerCopied = context.uiCopy(
      zh: '已達核准門檻；單次使用的 OID4VCI offer 已複製。',
      en: 'Approval threshold reached. The single-use OID4VCI offer was copied.',
    );
    final denied = context.uiCopy(zh: '申請已拒絕。', en: 'Application denied.');
    final waiting = context.uiCopy(
      zh: '已核准，等待其他管理員。',
      en: 'Approved; waiting for other administrators.',
    );
    final capability = await _authorize();
    final state = await widget.client.decideIssuanceRequest(
      tenantId: widget.tenantId,
      requestId: request.id,
      decision: decision,
      capability: capability,
    );
    if (state == 'approved') {
      final offer = await widget.client.createCredentialOffer(
        tenantId: widget.tenantId,
        requestId: request.id,
        capability: capability,
      );
      final encoded = jsonEncode(offer);
      await Clipboard.setData(ClipboardData(text: encoded));
      _message = offerCopied;
    } else {
      _message = decision == 'deny' ? denied : waiting;
    }
    _requests = await widget.client.listIssuanceRequests(
      tenantId: widget.tenantId,
      capability: capability,
    );
  });

  Future<void> _setStatus(String status) => _run(() async {
    final statusUpdated = context.uiCopy(
      zh: '憑證狀態已更新為 $status。',
      en: 'Credential status updated to $status.',
    );
    final credentialId = _credentialId.text.trim();
    if (credentialId.isEmpty) throw const FormatException('Credential ID');
    await widget.client.setCredentialStatus(
      tenantId: widget.tenantId,
      credentialId: credentialId,
      status: status,
      capability: await _authorize(),
    );
    _message = statusUpdated;
  });

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '會員憑證簽發', en: 'Membership issuance'),
      leadingLabel: context.uiCopy(zh: '返回', en: 'Back'),
      trailing: IconButton(
        onPressed: _busy ? null : _refresh,
        icon: const Icon(Icons.refresh),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.uiCopy(
              zh: '申請資料只顯示雜湊、會員類別與 policy snapshot；法律身分文件不會出現在這裡。',
              en: 'Applications expose only hashes, membership class, and the policy snapshot. Legal identity evidence is not shown here.',
            ),
            style: const TextStyle(color: AnsibleDesign.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (_requests.isEmpty && !_busy)
            Text(context.uiCopy(zh: '沒有待審申請', en: 'No pending applications')),
          for (final request in _requests)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.membershipClass,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SelectableText('request · ${request.id}'),
                    SelectableText(
                      'applicant · ${request.applicantHash.substring(0, 16)}…',
                    ),
                    Text(
                      '${request.approvalCount}/${request.approvalThreshold} approvals',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _decide(request, 'approve'),
                            child: Text(
                              context.uiCopy(zh: '核准', en: 'Approve'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _decide(request, 'deny'),
                            child: Text(context.uiCopy(zh: '拒絕', en: 'Deny')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 28),
          Text(
            context.uiCopy(zh: '憑證狀態', en: 'Credential status'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextField(
            controller: _credentialId,
            decoration: const InputDecoration(labelText: 'Credential ID'),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _setStatus('suspended'),
                child: Text(context.uiCopy(zh: '暫停', en: 'Suspend')),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _setStatus('active'),
                child: Text(context.uiCopy(zh: '恢復', en: 'Restore')),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _setStatus('revoked'),
                child: Text(context.uiCopy(zh: '撤銷', en: 'Revoke')),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            SelectableText(_message!),
          ],
        ],
      ),
    );
  }
}
