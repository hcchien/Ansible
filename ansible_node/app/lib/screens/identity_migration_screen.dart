import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/canonical_identity_store.dart';
import '../services/identity_anchor_service.dart';
import '../services/identity_migration_service.dart';
import '../services/relay_anchor_client.dart';
import '../services/relay_recovery_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'identity_security_screen.dart';

class IdentityMigrationScreen extends StatefulWidget {
  const IdentityMigrationScreen({
    super.key,
    required this.db,
    required this.did,
    this.service,
    this.onCompleted,
  });

  final AppDatabase db;
  final String did;
  final IdentityMigrationService? service;
  final ValueChanged<CanonicalIdentity>? onCompleted;

  @override
  State<IdentityMigrationScreen> createState() =>
      _IdentityMigrationScreenState();
}

class _IdentityMigrationScreenState extends State<IdentityMigrationScreen> {
  late final IdentityMigrationService _service;
  RelayAnchorClient? _ownedAnchorClient;
  RelayIdentityMigrationClient? _ownedMigrationClient;
  bool _consented = false;
  bool _migrating = false;
  bool _eligible = false;
  bool _loading = true;
  CanonicalIdentity? _completed;
  bool _recoveryCodesConfigured = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.service != null) {
      _service = widget.service!;
    } else {
      final repository = DriftIdentityAnchorRepository(widget.db);
      final anchorClient = RelayAnchorClient();
      final migrationClient = RelayIdentityMigrationClient();
      _ownedAnchorClient = anchorClient;
      _ownedMigrationClient = migrationClient;
      _service = IdentityMigrationService(
        anchorService: IdentityAnchorService(
          relayClient: anchorClient,
          anchorRepository: repository,
        ),
        anchorRepository: repository,
        anchorClient: anchorClient,
        migrationClient: migrationClient,
      );
    }
    _load();
  }

  @override
  void dispose() {
    _ownedAnchorClient?.close();
    _ownedMigrationClient?.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final eligible = await _service.isEligible();
      if (!mounted) return;
      setState(() {
        _eligible = eligible;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.uiCopy(
          zh: '無法讀取本機身分狀態，帳號尚未變更。',
          en: 'Local identity state could not be read. Your account was not changed.',
        );
      });
    }
  }

  Future<void> _start() async {
    if (!_consented || _migrating) return;
    setState(() {
      _migrating = true;
      _error = null;
    });

    HardwareAuthenticationSession? session;
    try {
      final requiresSigning = await _service.requiresSigning();
      if (!mounted) return;
      if (widget.service == null && requiresSigning) {
        session = await HardwareAuthenticationSession.begin(
          localizedReason: context.uiCopy(
            zh: '確認將目前帳號升級為 did:elix v1',
            en: 'Confirm upgrading this account to did:elix v1',
          ),
        );
      }
      final identity = await _service.migrate(
        reuseAuthenticationContext: session != null,
      );
      if (!mounted) return;
      setState(() {
        _completed = identity;
        _migrating = false;
        _eligible = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _migrating = false;
        _error = _messageFor(error);
      });
    } finally {
      await session?.close();
    }
  }

  void _finish() {
    final identity = _completed;
    if (identity == null) return;
    widget.onCompleted?.call(identity);
    Navigator.of(context).maybePop();
  }

  Future<void> _setupRecoveryCodes() async {
    final identity = _completed;
    if (identity == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecoveryCodesSetupScreen(
          did: identity.did,
          client: RelayRecoveryClient(),
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _recoveryCodesConfigured = true);
    }
  }

  String _messageFor(Object error) {
    final code = error is IdentityMigrationException ? error.code : '';
    return switch (code) {
      'canonical_identity_missing' => context.uiCopy(
        zh: '找不到本機完整身分資料；請先完成舊帳號復原。',
        en: 'Complete legacy account recovery before migrating.',
      ),
      'legacy_anchor_missing' => context.uiCopy(
        zh: 'Relay 上找不到舊帳號 anchor；請先在裝置與帳號復原中建立。',
        en: 'The legacy Relay anchor is missing. Set it up under Devices and recovery first.',
      ),
      'legacy_identity_key_mismatch' ||
      'account_state_mismatch' => context.uiCopy(
        zh: '本機金鑰與 Relay 帳號狀態不一致；為避免接管錯誤，升級已停止。',
        en: 'The local key and Relay account disagree, so migration stopped safely.',
      ),
      'account_frozen' => context.uiCopy(
        zh: '帳號目前已凍結，請先完成安全復原。',
        en: 'This account is frozen. Complete security recovery first.',
      ),
      'migration_confirmation_mismatch' ||
      'migration_checkpoint_mismatch' ||
      'v1_anchor_mismatch' => context.uiCopy(
        zh: '遷移證明與本機檢查點不一致；舊帳號仍保持不變，請聯絡支援。',
        en: 'Migration evidence did not match the local checkpoint. The legacy account remains unchanged.',
      ),
      _ => context.uiCopy(
        zh: '升級尚未完成。進度已安全保存，連線恢復後可按「繼續升級」。',
        en: 'Migration is not complete. Progress was saved safely; retry when the connection is available.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '升級 did:elix 身分', en: 'UPGRADE DID:ELIX'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 36),
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_completed != null)
            _completion()
          else if (!_eligible && _error == null)
            _notEligible()
          else
            _review(),
        ],
      ),
    );
  }

  Widget _review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.swap_horiz_rounded,
          size: 54,
          color: AnsibleDesign.accent,
        ),
        const SizedBox(height: 16),
        Text(
          context.uiCopy(
            zh: '保留帳號，更新識別方式',
            en: 'Keep your account, upgrade its identifier',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        _fact(
          Icons.alternate_email,
          context.uiCopy(
            zh: '帳號名稱不變；完成後新的貼文與同步改用 v1 DID。',
            en: 'Your handle stays the same; new posts and sync use the v1 DID.',
          ),
        ),
        _fact(
          Icons.history,
          context.uiCopy(
            zh: '舊貼文、簽章與憑證不會被改寫；舊 DID 會保留為可驗證別名。',
            en: 'Old posts, signatures, and credentials are not rewritten; the legacy DID remains a verifiable alias.',
          ),
        ),
        _fact(
          Icons.key_off_outlined,
          context.uiCopy(
            zh: '私鑰與生物辨識資料不會離開裝置；Relay 只收到公開 anchor 與雙簽證明。',
            en: 'Private keys and biometric data stay on-device; Relay receives only public anchors and dual-signed evidence.',
          ),
        ),
        _fact(
          Icons.password_outlined,
          context.uiCopy(
            zh: '原本的恢復碼綁定舊 DID。完成後請立即建立一組新的 v1 恢復碼。',
            en: 'Existing recovery codes are bound to the legacy DID. Create fresh v1 recovery codes after completion.',
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          key: const Key('identity_migration_consent'),
          contentPadding: EdgeInsets.zero,
          value: _consented,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: _migrating
              ? null
              : (value) => setState(() => _consented = value == true),
          title: Text(
            context.uiCopy(
              zh: '我了解這會將新的帳號操作切換到 v1，歷史資料仍保留原始 DID。',
              en: 'I understand new account operations move to v1 while historical data keeps its original DID.',
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              key: const Key('identity_migration_error'),
              style: const TextStyle(color: AnsibleDesign.ember, height: 1.45),
            ),
          ),
        FilledButton.icon(
          key: const Key('identity_migration_start'),
          onPressed: _consented && !_migrating ? _start : null,
          icon: _migrating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_user_outlined),
          label: Text(
            _migrating
                ? context.uiCopy(zh: '驗證並升級中…', en: 'Verifying and upgrading…')
                : _error == null
                ? context.uiCopy(zh: '確認並開始升級', en: 'Confirm and start')
                : context.uiCopy(zh: '繼續升級', en: 'Resume migration'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.uiCopy(
            zh: 'Relay 確認前不會切換帳號。中斷或關閉 App 後可安全繼續。',
            en: 'The account switches only after Relay confirmation. You can safely resume after closing the app.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AnsibleDesign.inkMuted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _completion() {
    final identity = _completed!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 64,
          color: AnsibleDesign.spore,
        ),
        const SizedBox(height: 16),
        Text(
          context.uiCopy(zh: '升級完成', en: 'Migration complete'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          identity.did,
          key: const Key('identity_migration_new_did'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: AnsibleDesign.mono, fontSize: 12),
        ),
        const SizedBox(height: 18),
        Text(
          context.uiCopy(
            zh: '新的操作現在使用 v1 DID。舊 DID 已保留為相同帳號的歷史別名。下一步請到「裝置與帳號復原」建立新的恢復碼。',
            en: 'New operations now use the v1 DID. The legacy DID remains a historical alias. Next, create fresh recovery codes under Devices and recovery.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.55),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          key: const Key('identity_migration_setup_recovery_codes'),
          onPressed: _recoveryCodesConfigured ? null : _setupRecoveryCodes,
          icon: Icon(
            _recoveryCodesConfigured
                ? Icons.check_circle_outline
                : Icons.password_outlined,
          ),
          label: Text(
            _recoveryCodesConfigured
                ? context.uiCopy(
                    zh: '新的恢復碼已建立',
                    en: 'Fresh recovery codes created',
                  )
                : context.uiCopy(
                    zh: '立即建立新的恢復碼',
                    en: 'Create fresh recovery codes now',
                  ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          key: const Key('identity_migration_done'),
          onPressed: _finish,
          child: Text(context.uiCopy(zh: '完成', en: 'Done')),
        ),
      ],
    );
  }

  Widget _notEligible() {
    return Column(
      children: [
        const Icon(
          Icons.verified_outlined,
          size: 58,
          color: AnsibleDesign.spore,
        ),
        const SizedBox(height: 14),
        Text(
          context.uiCopy(
            zh: '這個帳號已使用 did:elix v1，無需遷移。',
            en: 'This account already uses did:elix v1.',
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _fact(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: AnsibleDesign.inkMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.48))),
        ],
      ),
    );
  }
}
