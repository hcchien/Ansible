import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/oid4vci_wallet_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class MembershipCredentialScreen extends StatefulWidget {
  const MembershipCredentialScreen({
    super.key,
    required this.client,
    required this.onCredentialStored,
  });

  final Oid4vciWalletClient client;
  final Future<void> Function() onCredentialStored;

  @override
  State<MembershipCredentialScreen> createState() =>
      _MembershipCredentialScreenState();
}

class _MembershipCredentialScreenState
    extends State<MembershipCredentialScreen> {
  final _tenant = TextEditingController();
  final _forumHost = TextEditingController();
  final _board = TextEditingController();
  final _offer = TextEditingController();
  String _membershipClass = 'member';
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _tenant.dispose();
    _forumHost.dispose();
    _board.dispose();
    _offer.dispose();
    super.dispose();
  }

  Uri _issuer() {
    final tenant = _tenant.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{3,128}$').hasMatch(tenant)) {
      throw const FormatException('Invalid Hosted Issuer tenant ID');
    }
    final base = Uri.parse(AppEnvironment.issuerBaseUrl);
    return base.replace(path: '${base.path}/tenants/$tenant');
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

  Future<void> _apply() => _run(() async {
    final requestId = await widget.client.applyForMembership(
      credentialIssuer: _issuer(),
      forumHostId: _forumHost.text.trim(),
      boardId: _board.text.trim(),
      membershipClass: _membershipClass,
    );
    if (mounted) {
      setState(
        () => _message = context.uiCopy(
          zh: '申請已送出。申請代號：$requestId。核准後，管理員會提供一次性 offer。',
          en: 'Application submitted. Request ID: $requestId. An administrator will provide a single-use offer after approval.',
        ),
      );
    }
  });

  Future<void> _accept() => _run(() async {
    final decoded = jsonDecode(_offer.text.trim());
    if (decoded is! Map) throw const FormatException('Invalid offer');
    final offer = Oid4vciCredentialOffer.parse(
      Map<String, Object?>.from(decoded),
    );
    await widget.client.accept(offer);
    await widget.onCredentialStored();
    if (mounted) {
      setState(
        () => _message = context.uiCopy(
          zh: '會員憑證已驗證並加密保存到本機 Wallet。',
          en: 'Membership credential verified and encrypted in the local Wallet.',
        ),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '申請會員憑證', en: 'Membership credential'),
      leadingLabel: context.uiCopy(zh: '返回', en: 'Back'),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.uiCopy(
              zh: '每個看板使用獨立、不可匯出的硬體金鑰與 pairwise DID；完整會員憑證只保存於你的 Wallet。',
              en: 'Each board uses a separate non-exportable hardware key and pairwise DID. The complete membership credential remains only in your Wallet.',
            ),
            style: const TextStyle(color: AnsibleDesign.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('membership_tenant_id'),
            controller: _tenant,
            decoration: const InputDecoration(
              labelText: 'Hosted Issuer tenant ID',
            ),
          ),
          TextField(
            key: const Key('membership_forum_host_id'),
            controller: _forumHost,
            decoration: const InputDecoration(
              labelText: 'Forum Host ID',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('membership_board_id'),
            controller: _board,
            decoration: InputDecoration(
              labelText: context.uiCopy(
                zh: '憑證適用的看板 ID',
                en: 'Board ID for this credential',
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _membershipClass,
            decoration: InputDecoration(
              labelText: context.uiCopy(zh: '申請資格', en: 'Membership class'),
            ),
            items: [
              DropdownMenuItem(
                value: 'member',
                child: Text(context.uiCopy(zh: '會員', en: 'Member')),
              ),
              DropdownMenuItem(
                value: 'moderator',
                child: Text(context.uiCopy(zh: '管理員', en: 'Moderator')),
              ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _membershipClass = value!),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('membership_apply'),
            onPressed: _busy ? null : _apply,
            child: Text(
              context.uiCopy(zh: '以硬體金鑰送出申請', en: 'Apply with hardware key'),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            context.uiCopy(zh: '接受已核准的 offer', en: 'Accept an approved offer'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextField(
            key: const Key('membership_offer'),
            controller: _offer,
            minLines: 4,
            maxLines: 9,
            decoration: InputDecoration(
              hintText: context.uiCopy(
                zh: '貼上管理員提供的一次性 OID4VCI offer JSON',
                en: 'Paste the single-use OID4VCI offer JSON',
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('membership_accept_offer'),
            onPressed: _busy ? null : _accept,
            child: Text(
              context.uiCopy(
                zh: '驗證並存入 Wallet',
                en: 'Verify and save to Wallet',
              ),
            ),
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
