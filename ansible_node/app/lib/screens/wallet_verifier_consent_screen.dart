import 'dart:convert';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

import '../l10n/app_l10n.dart';
import '../services/oid4vp_presentation_service.dart';
import '../services/oid4vp_request.dart';

typedef WalletNowProvider = DateTime Function();

class WalletVerifierConsentScreen extends StatefulWidget {
  const WalletVerifierConsentScreen({
    super.key,
    required this.holderDid,
    required this.request,
    required this.presentationService,
    WalletNowProvider? now,
  }) : now = now ?? DateTime.now;

  final String holderDid;
  final Oid4vpAuthorizationRequest request;
  final Oid4vpPresentationApprover presentationService;
  final WalletNowProvider now;

  @override
  State<WalletVerifierConsentScreen> createState() =>
      _WalletVerifierConsentScreenState();
}

class _WalletVerifierConsentScreenState
    extends State<WalletVerifierConsentScreen> {
  var _submitting = false;
  var _preparing = false;
  PreparedOid4vpPresentation? _prepared;

  @override
  void initState() {
    super.initState();
    if (widget.presentationService is Oid4vpPresentationService) {
      _preparing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
    }
  }

  Future<void> _prepare() async {
    try {
      final prepared =
          await (widget.presentationService as Oid4vpPresentationService)
              .prepare(
                holderDid: widget.holderDid,
                request: widget.request,
                now: widget.now().toUtc(),
              );
      if (mounted) {
        setState(() {
          _prepared = prepared;
          _preparing = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _errorMessage = _formatError(error);
        });
      }
    }
  }

  Oid4vpSubmissionResult? _result;
  String? _errorMessage;

  Future<void> _approve() async {
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final result = _prepared != null
          ? await (widget.presentationService as Oid4vpPresentationService)
                .approvePrepared(_prepared!, now: widget.now().toUtc())
          : await widget.presentationService.approve(
              holderDid: widget.holderDid,
              request: widget.request,
              now: widget.now().toUtc(),
            );
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = _formatError(error);
      });
    }
  }

  String _formatError(Object error) {
    if (error is Oid4vpSubmissionException) {
      switch (error.code) {
        case 'no_matching_credential':
          return context.uiCopy(
            zh: 'Wallet 沒有可用的真人憑證。',
            en: 'Wallet has no available human credential.',
          );
        case 'missing_holder_key':
          return context.uiCopy(
            zh: 'Wallet 簽章金鑰尚未就緒。',
            en: 'Wallet signing key is not ready.',
          );
        case 'direct_post_failed':
          return context.uiCopy(
            zh: 'Verifier 未接受這次 VP。',
            en: 'The Verifier did not accept this VP.',
          );
      }
    }
    return context.uiCopy(
      zh: 'VP 送出失敗，請重新掃描。',
      en: 'VP submission failed. Scan again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Theme(
      data: AnsibleDesign.theme(),
      child: Scaffold(
        backgroundColor: AnsibleDesign.paper,
        appBar: AppBar(
          title: Text(context.uiCopy(zh: '驗證方請求', en: 'Verifier Request')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Icon(Icons.verified_user_outlined, size: 48),
            const SizedBox(height: 14),
            Text(
              result == null
                  ? context.uiCopy(zh: '驗證方請求', en: 'Verifier Request')
                  : context.uiCopy(zh: 'VP 已送出', en: 'VP Submitted'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _InfoRow(
              label: context.uiCopy(zh: '驗證方', en: 'Verifier'),
              value: widget.request.verifierLabel,
            ),
            _InfoRow(
              label: context.uiCopy(zh: '憑證', en: 'Credential'),
              value: widget.request.requiredCredentialType,
            ),
            _InfoRow(
              label: context.uiCopy(zh: '挑戰值', en: 'Challenge'),
              value: widget.request.nonce,
            ),
            _InfoRow(
              label: context.uiCopy(zh: '回應位置', en: 'Response'),
              value: widget.request.responseUri.toString(),
            ),
            const SizedBox(height: 16),
            _Section(
              title: context.uiCopy(zh: '要求的屬性', en: 'Requested claims'),
              body: widget.request.requestedClaimLabels.join(', '),
            ),
            const SizedBox(height: 12),
            _Section(
              title: context.uiCopy(zh: '實際會傳送的資料', en: 'Actual disclosure'),
              body: context.uiCopy(
                zh: '此格式會傳送完整憑證，包含持有人識別碼、發行者、有效期限、狀態查詢位置與全部屬性。接收方可能據此連結多次出示。請檢查以下內容再同意。',
                en: 'This format sends the complete credential: holder identifier, issuer, validity, status endpoint and all claims. The recipient may correlate presentations. Review the contents before consenting.',
              ),
            ),
            if (_preparing) const LinearProgressIndicator(),
            if (_prepared != null)
              SelectableText(
                const JsonEncoder.withIndent(
                  '  ',
                ).convert(_prepared!.presentation),
                key: const Key('actual_disclosure'),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (result == null)
              FilledButton.icon(
                onPressed:
                    _submitting ||
                        _preparing ||
                        (widget.presentationService
                                is Oid4vpPresentationService &&
                            _prepared == null)
                    ? null
                    : _approve,
                icon: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.outbound),
                label: Text(
                  context.uiCopy(zh: '同意並送出 VP', en: 'Consent and Submit VP'),
                ),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_circle),
                label: Text(context.uiCopy(zh: '完成', en: 'Done')),
              ),
            const SizedBox(height: 8),
            if (result == null)
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      ),
    );
  }
}
