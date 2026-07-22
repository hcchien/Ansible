import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../services/hosted_issuer_admin_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

typedef HostedIssuerClientFactory = HostedIssuerAdminClient Function();

class HostedIssuerOnboardingScreen extends StatefulWidget {
  const HostedIssuerOnboardingScreen({
    super.key,
    required this.ownerDid,
    this.clientFactory,
    this.storage = const FlutterSecureStorage(),
  });

  final String ownerDid;
  final HostedIssuerClientFactory? clientFactory;
  final FlutterSecureStorage storage;

  @override
  State<HostedIssuerOnboardingScreen> createState() =>
      _HostedIssuerOnboardingScreenState();
}

class _HostedIssuerOnboardingScreenState
    extends State<HostedIssuerOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _organizationDid = TextEditingController();
  final _serviceSlug = TextEditingController();
  int _administratorCount = 3;
  int _threshold = 2;
  bool _busy = false;
  HostedIssuerTenant? _tenant;
  String? _error;

  @override
  void dispose() {
    _organizationDid.dispose();
    _serviceSlug.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client =
          widget.clientFactory?.call() ??
          HostedIssuerAdminClient(
            baseUrl: AppEnvironment.issuerBaseUrl,
            ownerDid: widget.ownerDid,
          );
      final tenant = await client.bootstrap(
        organizationDid: _organizationDid.text.trim(),
        serviceSlug: _serviceSlug.text.trim(),
        approvalThreshold: _threshold,
        administratorCount: _administratorCount,
      );
      await client.enrollAdministratorPasskey(tenant.id);
      await widget.storage.write(
        key: 'elix.hosted_issuer.tenant_id',
        value: tenant.id,
      );
      if (mounted) setState(() => _tenant = tenant);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '代管簽發者', en: 'Hosted Issuer'),
      leadingLabel: context.uiCopy(zh: '返回', en: 'Back'),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.uiCopy(
              zh: '由 Elix 代管營運金鑰，但組織 root authority 仍由管理員裝置持有。',
              en: 'Elix hosts the operational key while the organization root authority remains on administrator devices.',
            ),
            style: const TextStyle(color: AnsibleDesign.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (_tenant != null) ...[
            Text(
              context.uiCopy(zh: '代管已建立', en: 'Hosted Issuer created'),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AnsibleDesign.ink,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(_tenant!.id),
            const SizedBox(height: 8),
            Text(
              context.uiCopy(
                zh: '管理員 Passkey 已註冊。下一步需邀請其他管理員，達到 $_threshold-of-$_administratorCount 後才能啟用 operational key delegation。',
                en: 'The administrator passkey is registered. Invite the remaining administrators; operational key delegation requires $_threshold-of-$_administratorCount approval.',
              ),
            ),
          ] else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const Key('hosted_issuer_organization_did'),
                    controller: _organizationDid,
                    decoration: InputDecoration(
                      labelText: context.uiCopy(
                        zh: '組織 DID',
                        en: 'Organization DID',
                      ),
                    ),
                    validator: (value) =>
                        value != null && value.startsWith('did:')
                        ? null
                        : context.uiCopy(
                            zh: '請輸入有效的組織 DID',
                            en: 'Enter a valid organization DID',
                          ),
                  ),
                  TextFormField(
                    key: const Key('hosted_issuer_service_slug'),
                    controller: _serviceSlug,
                    decoration: InputDecoration(
                      labelText: context.uiCopy(zh: '服務代號', en: 'Service slug'),
                      hintText: 'ntp-party',
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[a-z0-9][a-z0-9-]{2,47}$',
                        ).hasMatch(value ?? '')
                        ? null
                        : context.uiCopy(
                            zh: '使用 3–48 個小寫英數字或連字號',
                            en: 'Use 3–48 lowercase letters, digits, or hyphens',
                          ),
                  ),
                  const SizedBox(height: 20),
                  _CountPicker(
                    label: context.uiCopy(zh: '管理員人數', en: 'Administrators'),
                    value: _administratorCount,
                    min: 1,
                    max: 5,
                    onChanged: (value) => setState(() {
                      _administratorCount = value;
                      if (_threshold > value) _threshold = value;
                    }),
                  ),
                  _CountPicker(
                    label: context.uiCopy(zh: '核准門檻', en: 'Approval threshold'),
                    value: _threshold,
                    min: 1,
                    max: _administratorCount,
                    onChanged: (value) => setState(() => _threshold = value),
                  ),
                  if (_threshold == 1)
                    Text(
                      context.uiCopy(
                        zh: '單一管理員模式屬降低信任；正式組織建議至少 2-of-3。',
                        en: 'Single-admin mode is reduced trust; use at least 2-of-3 for a production organization.',
                      ),
                      style: const TextStyle(color: AnsibleDesign.ochre),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('hosted_issuer_create'),
                    onPressed: _busy ? null : _create,
                    child: Text(
                      _busy
                          ? context.uiCopy(zh: '建立中…', en: 'Creating…')
                          : context.uiCopy(
                              zh: '建立並註冊 Passkey',
                              en: 'Create and register passkey',
                            ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CountPicker extends StatelessWidget {
  const _CountPicker({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        Text('$value'),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
