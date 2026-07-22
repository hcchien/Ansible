import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/hosted_issuer_admin_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'hosted_issuer_issuance_screen.dart';

class HostedIssuerAdministratorsScreen extends StatefulWidget {
  const HostedIssuerAdministratorsScreen({
    super.key,
    required this.localDid,
    this.storage = const FlutterSecureStorage(),
    this.clientFactory,
  });

  final String localDid;
  final FlutterSecureStorage storage;
  final HostedIssuerAdminClient Function()? clientFactory;

  @override
  State<HostedIssuerAdministratorsScreen> createState() =>
      _HostedIssuerAdministratorsScreenState();
}

class _HostedIssuerAdministratorsScreenState
    extends State<HostedIssuerAdministratorsScreen> {
  final _tenant = TextEditingController();
  final _enrollment = TextEditingController();
  bool _busy = false;
  String? _message;

  HostedIssuerAdminClient get _client =>
      widget.clientFactory?.call() ??
      HostedIssuerAdminClient(
        baseUrl: AppEnvironment.issuerBaseUrl,
        ownerDid: widget.localDid,
      );

  @override
  void initState() {
    super.initState();
    widget.storage.read(key: 'elix.hosted_issuer.tenant_id').then((value) {
      if (mounted && value != null) setState(() => _tenant.text = value);
    });
  }

  @override
  void dispose() {
    _tenant.dispose();
    _enrollment.dispose();
    super.dispose();
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

  Future<void> _createEnrollment() => _run(() async {
    final request = await _client.createAdministratorEnrollment(
      tenantId: _tenant.text.trim(),
    );
    final encoded = jsonEncode(request);
    _enrollment.text = encoded;
    await Clipboard.setData(ClipboardData(text: encoded));
    if (mounted) {
      setState(
        () => _message = context.uiCopy(
          zh: '加入請求已複製；請安全地交給現有管理員核准。',
          en: 'Enrollment request copied. Send it securely to an existing administrator.',
        ),
      );
    }
  });

  Future<void> _approveEnrollment() => _run(() async {
    final decoded = jsonDecode(_enrollment.text);
    if (decoded is! Map) throw const FormatException('Invalid enrollment');
    final client = _client;
    final capability = await client.authenticateAdministrator(
      tenantId: _tenant.text.trim(),
      scopes: const {'issuer_admin:admins'},
    );
    await client.addAdministrator(
      tenantId: _tenant.text.trim(),
      applicantEnrollment: Map<String, Object?>.from(decoded),
      capability: capability,
    );
    if (mounted) {
      setState(
        () => _message = context.uiCopy(
          zh: '管理員已加入；對方現在可以註冊自己的 Passkey。',
          en: 'Administrator added. They can now enroll their passkey.',
        ),
      );
    }
  });

  Future<void> _enrollPasskey() => _run(() async {
    await _client.enrollAdministratorPasskey(_tenant.text.trim());
    await widget.storage.write(
      key: 'elix.hosted_issuer.tenant_id',
      value: _tenant.text.trim(),
    );
    if (mounted) {
      setState(
        () => _message = context.uiCopy(
          zh: '管理員 Passkey 已註冊。',
          en: 'Administrator passkey registered.',
        ),
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '簽發者管理員', en: 'Issuer administrators'),
      leadingLabel: context.uiCopy(zh: '返回', en: 'Back'),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('hosted_issuer_tenant_id'),
            controller: _tenant,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Tenant ID'),
          ),
          const SizedBox(height: 18),
          Text(
            context.uiCopy(zh: '加入現有組織', en: 'Join an organization'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AnsibleDesign.ink,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _createEnrollment,
            child: Text(
              context.uiCopy(
                zh: '建立硬體簽章加入請求',
                en: 'Create hardware-signed enrollment',
              ),
            ),
          ),
          OutlinedButton(
            onPressed: _busy ? null : _enrollPasskey,
            child: Text(
              context.uiCopy(
                zh: '已獲核准，註冊 Passkey',
                en: 'Approved — enroll passkey',
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.uiCopy(zh: '核准新管理員', en: 'Approve an administrator'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AnsibleDesign.ink,
            ),
          ),
          TextField(
            key: const Key('hosted_issuer_enrollment_payload'),
            controller: _enrollment,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: context.uiCopy(
                zh: '貼上對方的加入請求 JSON',
                en: 'Paste the enrollment request JSON',
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _approveEnrollment,
            child: Text(
              context.uiCopy(
                zh: '用 Passkey 與 root key 核准',
                en: 'Approve with passkey and root key',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('hosted_issuer_open_issuance'),
            onPressed: _busy || _tenant.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HostedIssuerIssuanceScreen(
                        tenantId: _tenant.text.trim(),
                        client: _client,
                      ),
                    ),
                  ),
            icon: const Icon(Icons.badge_outlined),
            label: Text(
              context.uiCopy(
                zh: '審核與簽發會員憑證',
                en: 'Review and issue membership credentials',
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
