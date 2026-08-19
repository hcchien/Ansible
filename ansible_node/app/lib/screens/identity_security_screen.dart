import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_environment.dart';
import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/canonical_identity_store.dart';
import '../services/identity_anchor_service.dart';
import '../services/relay_anchor_client.dart';
import '../services/relay_identity_bootstrap_service.dart';
import '../services/relay_recovery_client.dart';
import '../services/secure_device_key_store.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'recovery_approve_scanner_screen.dart';

class IdentitySecurityScreen extends StatefulWidget {
  const IdentitySecurityScreen({
    super.key,
    required this.db,
    required this.did,
    this.client,
  });

  final AppDatabase db;
  final String did;
  final RelayRecoveryClient? client;

  @override
  State<IdentitySecurityScreen> createState() => _IdentitySecurityScreenState();
}

class _IdentitySecurityScreenState extends State<IdentitySecurityScreen> {
  late final RelayRecoveryClient _client =
      widget.client ?? RelayRecoveryClient();
  List<AnchorDeviceRecord> _devices = const [];
  List<RecoveryAuditEvent> _audit = const [];
  RecoveryCodeStatus? _codeStatus;
  DeviceKey? _localDevice;
  bool _loading = true;
  bool _anchorMissing = false;
  bool _creatingInitialAnchor = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _anchorMissing = false;
        _error = null;
      });
    }
    try {
      final values = await Future.wait<Object?>([
        _client.devices(widget.did),
        _client.codeStatus(widget.did),
        _client.audit(widget.did),
        const SecureDeviceKeyStore().load(),
      ]);
      if (!mounted) return;
      setState(() {
        _devices = values[0] as List<AnchorDeviceRecord>;
        _codeStatus = values[1] as RecoveryCodeStatus;
        _audit = values[2] as List<RecoveryAuditEvent>;
        _localDevice = values[3] as DeviceKey?;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _anchorMissing = error.toString().contains('anchor_not_found');
        _error = _anchorMissing ? null : userFacingError(context, error);
      });
    }
  }

  /// A reinstall can retain the self-custodied identity key while clearing the
  /// local recovery-chain cache. Creating this initial anchor is an explicit
  /// user action: it publishes only the DID's public verification material and
  /// enrolled-device attestation to the selected Relay.
  Future<void> _createInitialAnchor() async {
    setState(() => _creatingInitialAnchor = true);
    try {
      final canonicalIdentity = await const SecureCanonicalIdentityStore()
          .load();
      final handle = await RelayIdentityBootstrapService.ensureVerified(
        did: widget.did,
        baseUrl: AppEnvironment.atProtoBaseUrl,
      );
      await IdentityAnchorService(
        relayClient: RelayAnchorClient(),
        anchorRepository: DriftIdentityAnchorRepository(widget.db),
      ).publishInitialAnchor(
        did: widget.did,
        handle: handle,
        identityKey: const ActiveIdentityKey(),
        genesisCommitment: canonicalIdentity?.genesisCommitment,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    } finally {
      if (mounted) setState(() => _creatingInitialAnchor = false);
    }
  }

  Future<void> _revoke(AnchorDeviceRecord device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.uiCopy(zh: '撤銷這台裝置？', en: 'Revoke this device?')),
        content: Text(
          context.uiCopy(
            zh: '撤銷會立即寫入身分 anchor。私密看板也會要求輪替 epoch，讓這台裝置無法取得之後的內容。',
            en: 'Revocation is written to the identity anchor immediately. Private boards will require an epoch rotation so this device cannot read future content.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.uiCopy(zh: '撤銷', en: 'Revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final service = IdentityAnchorService(
        relayClient: RelayAnchorClient(),
        anchorRepository: DriftIdentityAnchorRepository(widget.db),
      );
      await service.revokeDevice(did: widget.did, deviceId: device.deviceId);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    }
  }

  Future<void> _setupCodes() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            RecoveryCodesSetupScreen(did: widget.did, client: _client),
      ),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '裝置與帳號復原', en: 'DEVICES & RECOVERY'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 36),
          children: [
            _sectionTitle(context.uiCopy(zh: '已核准裝置', en: 'APPROVED DEVICES')),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: AnsibleDesign.ember))
            else if (_anchorMissing) ...[
              Text(
                context.uiCopy(
                  zh: '這台裝置的 DID 尚未在目前 Relay 建立復原 anchor。建立後才能核准其他裝置、設定恢復碼與管理安全紀錄。',
                  en: 'This device has no recovery anchor on the current Relay yet. Create one before approving devices, setting recovery codes, or viewing security history.',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('create_initial_anchor_button'),
                onPressed: _creatingInitialAnchor ? null : _createInitialAnchor,
                icon: _creatingInitialAnchor
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: Text(
                  context.uiCopy(
                    zh: '建立此裝置的復原設定',
                    en: 'Set up recovery for this device',
                  ),
                ),
              ),
            ] else if (_devices.isEmpty)
              Text(
                context.uiCopy(
                  zh: '尚無可管理的裝置 anchor。',
                  en: 'No manageable device anchor yet.',
                ),
              )
            else
              ..._devices.map(_deviceTile),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              key: const Key('approve_new_device_button'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      RecoveryApproveScannerScreen(localDid: widget.did),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                context.uiCopy(zh: '核准新裝置', en: 'Approve a new device'),
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle(context.uiCopy(zh: '恢復方式', en: 'RECOVERY METHODS')),
            ListTile(
              key: const Key('recovery_codes_row'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password_outlined),
              title: Text(
                context.uiCopy(zh: '一次性恢復碼', en: 'One-time recovery codes'),
              ),
              subtitle: Text(
                _codeStatus?.configured == true
                    ? context.uiCopy(
                        zh: '剩餘 ${_codeStatus!.remaining} 組',
                        en: '${_codeStatus!.remaining} remaining',
                      )
                    : context.uiCopy(zh: '尚未設定', en: 'Not configured'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _setupCodes,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phonelink_lock_outlined),
              title: Text(
                context.uiCopy(zh: '遺失或更換手機', en: 'Lost or replacement phone'),
              ),
              subtitle: Text(
                context.uiCopy(
                  zh: '使用舊裝置核准；legacy 備份僅為降低信任模式',
                  en: 'Approve with an old device; legacy backup is reduced trust only',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      RecoveryApproveScannerScreen(localDid: widget.did),
                ),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.enhanced_encryption_outlined),
              title: Text(
                context.uiCopy(zh: '私密看板金鑰', en: 'Private board keys'),
              ),
              subtitle: Text(
                context.uiCopy(
                  zh: '新裝置加入後，需由既有裝置重新包裝；撤銷後必須輪替 epoch',
                  en: 'A surviving device re-wraps keys after approval; revocation requires epoch rotation',
                ),
              ),
            ),
            const SizedBox(height: 28),
            _sectionTitle(context.uiCopy(zh: '安全紀錄', en: 'SECURITY AUDIT')),
            if (_audit.isEmpty && !_loading)
              Text(context.uiCopy(zh: '尚無紀錄', en: 'No events yet'))
            else
              ..._audit
                  .take(20)
                  .map(
                    (event) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(_eventLabel(event)),
                      subtitle: Text(
                        '${event.occurredAt} · ${event.state ?? event.reasonCode}',
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(AnchorDeviceRecord device) {
    final current = device.deviceId == _localDevice?.deviceId;
    return ListTile(
      key: Key('approved_device_${device.deviceId}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(current ? Icons.smartphone : Icons.devices_other),
      title: Text(
        current
            ? context.uiCopy(zh: '這台裝置', en: 'This device')
            : context.uiCopy(zh: '已核准裝置', en: 'Approved device'),
      ),
      subtitle: Text(
        '${device.deviceId.length > 12 ? device.deviceId.substring(0, 12) : device.deviceId} · ${device.custodyClass.storageValue}',
      ),
      trailing: current
          ? null
          : IconButton(
              tooltip: context.uiCopy(zh: '撤銷', en: 'Revoke'),
              onPressed: () => _revoke(device),
              icon: const Icon(
                Icons.remove_circle_outline,
                color: AnsibleDesign.ember,
              ),
            ),
    );
  }

  String _eventLabel(RecoveryAuditEvent event) => switch (event.eventType) {
    'recovery_pending' => context.uiCopy(zh: '帳號復原等待中', en: 'Recovery pending'),
    'recovery_promoted' => context.uiCopy(
      zh: '帳號復原已生效',
      en: 'Recovery activated',
    ),
    'recovery_vetoed' => context.uiCopy(zh: '帳號復原遭否決', en: 'Recovery vetoed'),
    'devices_changed' => context.uiCopy(
      zh: '核准裝置已變更',
      en: 'Approved devices changed',
    ),
    'identity_rotated' => context.uiCopy(
      zh: '身分金鑰已輪替',
      en: 'Identity key rotated',
    ),
    'recovery_codes_configured' => context.uiCopy(
      zh: '恢復碼已更新',
      en: 'Recovery codes updated',
    ),
    'recovery_started' => context.uiCopy(
      zh: '已使用恢復碼',
      en: 'Recovery code used',
    ),
    _ => event.reasonCode,
  };

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      value,
      style: const TextStyle(
        fontFamily: AnsibleDesign.mono,
        fontSize: 12,
        letterSpacing: 1.2,
        color: AnsibleDesign.inkMuted,
      ),
    ),
  );
}

class RecoveryCodesSetupScreen extends StatefulWidget {
  const RecoveryCodesSetupScreen({
    super.key,
    required this.did,
    required this.client,
  });
  final String did;
  final RelayRecoveryClient client;

  @override
  State<RecoveryCodesSetupScreen> createState() =>
      _RecoveryCodesSetupScreenState();
}

class _RecoveryCodesSetupScreenState extends State<RecoveryCodesSetupScreen> {
  late final List<String> _codes = RelayRecoveryClient.generateCodes();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (normalizedRecoveryCode(_confirm.text) !=
        normalizedRecoveryCode(_codes[2])) {
      setState(
        () => _error = context.uiCopy(
          zh: '請正確輸入第 3 組恢復碼，確認你已保存。',
          en: 'Enter recovery code 3 exactly to confirm it is saved.',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.client.configureCodes(did: widget.did, codes: _codes);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userFacingError(context, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnsibleScreenScaffold(
    title: context.uiCopy(zh: '設定恢復碼', en: 'RECOVERY CODES'),
    leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 32),
      children: [
        Text(
          context.uiCopy(
            zh: '每組只能使用一次。請離線保存；Elix Relay 只會收到雜湊，無法替你找回原始碼。重新產生會撤銷舊碼。',
            en: 'Each code works once. Store them offline; the Relay receives hashes only and cannot recover the originals. Regenerating revokes old codes.',
          ),
          style: const TextStyle(height: 1.55),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AnsibleDesign.rule),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            _codes
                .asMap()
                .entries
                .map((entry) => '${entry.key + 1}. ${entry.value}')
                .join('\n'),
            key: const Key('recovery_codes_list'),
            style: const TextStyle(fontFamily: AnsibleDesign.mono, height: 1.8),
          ),
        ),
        TextButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: _codes.join('\n'))),
          icon: const Icon(Icons.copy),
          label: Text(context.uiCopy(zh: '複製全部', en: 'Copy all')),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('recovery_code_confirmation'),
          controller: _confirm,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.uiCopy(
              zh: '輸入第 3 組恢復碼',
              en: 'Enter recovery code 3',
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: AnsibleDesign.ember),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('confirm_recovery_codes_button'),
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? context.uiCopy(zh: '設定中…', en: 'Saving…')
                : context.uiCopy(
                    zh: '確認已保存並啟用',
                    en: 'Confirm saved and enable',
                  ),
          ),
        ),
      ],
    ),
  );
}
