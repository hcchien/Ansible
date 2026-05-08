import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../services/external_url_launcher.dart';
import '../services/vc_issuer_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'credential_issuance_wizard.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.holderDid,
    required this.repository,
    this.vcIssuerClient,
    this.urlLauncher,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 2),
  });

  final String holderDid;
  final WalletRepository repository;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final Duration pollInterval;
  final Duration pollTimeout;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<List<WalletCredential>> _credentials;
  var _showWizard = false;

  @override
  void initState() {
    super.initState();
    _credentials = widget.repository.listCredentials();
  }

  Future<void> _reload() async {
    setState(() {
      _credentials = widget.repository.listCredentials();
    });
    await _credentials;
  }

  Future<void> _deleteCredential(WalletCredential credential) async {
    await widget.repository.deleteCredential(credential.credentialId);
    await _reload();
  }

  void _openAddCredential() {
    setState(() => _showWizard = true);
  }

  Future<void> _handleCredentialStored() async {
    if (!mounted) return;
    setState(() => _showWizard = false);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: 'WALLET',
      leadingLabel: '← 設定',
      trailing: IconButton(
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
        tooltip: '重新整理',
      ),
      child: FutureBuilder<List<WalletCredential>>(
        future: _credentials,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final credentials = snapshot.data ?? const <WalletCredential>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            children: [
              const AnsibleMonoLabel('身分 · IDENTITIES'),
              const SizedBox(height: 6),
              const Text(
                '錢包',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'one device, many selves',
                style: TextStyle(
                  fontSize: 13,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '這些都是你。但你選擇在哪裡是哪一個。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              _IdentityCard(
                primary: true,
                name: '本人',
                en: 'ROOT · MASTER PASSKEY',
                type: 'master passkey',
                sub: '此裝置上產生的源頭。不能改名、不能複製、不能離開這台。',
                uses: '所有圈與發布物的根',
                age: '建立 312 天前',
                keyFragment: _fragment(widget.holderDid),
              ),
              const SizedBox(height: 12),
              const _IdentityCard(
                accent: true,
                name: '公開 · Tris',
                en: 'PUBLIC HANDLE',
                type: '衍生身分',
                sub: '在討論串裡露出的名字。讀者只會看到這個。',
                uses: '公開討論 · 23 處',
                age: '278 天',
                keyFragment: 'pk · 8c4d ... 22fa',
              ),
              const SizedBox(height: 12),
              const _IdentityCard(
                name: '讀書會 · Tris',
                en: 'CIRCLE HANDLE',
                type: '圈內身分',
                sub: '只在「週四讀書會」內可見。離開圈就消失。',
                uses: '1 個圈',
                age: '92 天',
                keyFragment: 'pk · c91a ... 6d02',
              ),
              const SizedBox(height: 12),
              const _IdentityCard(
                dim: true,
                name: '匿名瀏覽',
                en: 'OBSERVER',
                type: '只讀身分',
                sub: '拿來閱讀別人的公開內容；不留下任何痕跡。',
                uses: '未啟用',
                age: '未使用',
                keyFragment: 'pk · observer',
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _openAddCredential,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('產生新身分'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AnsibleDesign.rule,
                    width: 0.5,
                    style: BorderStyle.solid,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              if (_showWizard) ...[
                _buildCredentialWizard(),
                const SizedBox(height: 16),
              ],
              const AnsibleMonoLabel('憑證 · CREDENTIALS'),
              const SizedBox(height: 8),
              if (credentials.isEmpty)
                _EmptyWalletState(onAddCredential: _openAddCredential)
              else
                for (final credential in credentials) ...[
                  _CredentialTile(
                    credential: credential,
                    onDelete: () => _deleteCredential(credential),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AnsibleDesign.paperDeep.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '身分都從「本人」衍生而來。彼此之間不可互推。\n就算公開的我被看穿了，圈內的我仍是隱密的。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.7,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCredentialWizard() {
    return CredentialIssuanceWizard(
      holderDid: widget.holderDid,
      vcIssuerClient: widget.vcIssuerClient,
      urlLauncher: widget.urlLauncher,
      walletRepository: widget.repository,
      pollInterval: widget.pollInterval,
      pollTimeout: widget.pollTimeout,
      onCredentialStored: _handleCredentialStored,
    );
  }

  static String _fragment(String value) {
    if (value.length <= 16) return 'pk · $value';
    return 'pk · ${value.substring(0, 6)} ... ${value.substring(value.length - 4)}';
  }
}

class _EmptyWalletState extends StatelessWidget {
  const _EmptyWalletState({required this.onAddCredential});

  final VoidCallback onAddCredential;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AnsibleDesign.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: AnsibleDesign.accent,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '還沒有憑證',
                  style: TextStyle(
                    color: AnsibleDesign.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '驗證憑證核發後會出現在這裡。',
                  style: TextStyle(
                    color: AnsibleDesign.inkMuted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAddCredential,
            icon: const Icon(Icons.add),
            tooltip: '新增憑證',
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.en,
    required this.type,
    required this.sub,
    required this.uses,
    required this.age,
    required this.keyFragment,
    this.primary = false,
    this.accent = false,
    this.dim = false,
  });

  final String name;
  final String en;
  final String type;
  final String sub;
  final String uses;
  final String age;
  final String keyFragment;
  final bool primary;
  final bool accent;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dim ? 0.65 : 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: primary
              ? AnsibleDesign.paperDeep.withValues(alpha: 0.45)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primary ? AnsibleDesign.ink : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Stack(
          children: [
            if (accent)
              const Positioned(
                left: -16,
                top: 0,
                bottom: 0,
                child: SizedBox(
                  width: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AnsibleDesign.accent),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        en,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 9,
                          letterSpacing: 1.4,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),
                    ),
                    Text(
                      age,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9,
                        letterSpacing: 1,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: primary ? 22 : 17,
                        fontWeight: FontWeight.w500,
                        color: AnsibleDesign.ink,
                      ),
                    ),
                    if (primary)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AnsibleDesign.accent,
                            width: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          '主',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 8,
                            letterSpacing: 1.4,
                            color: AnsibleDesign.accent,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  keyFragment,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: AnsibleDesign.ruleSoft, height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      type,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      uses,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9,
                        letterSpacing: 1,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialTile extends StatelessWidget {
  const _CredentialTile({required this.credential, required this.onDelete});

  final WalletCredential credential;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _statusColor(credential.status).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.verified_user_outlined,
              color: _statusColor(credential.status),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  credential.displayName,
                  style: const TextStyle(
                    color: AnsibleDesign.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _StatusChip(status: credential.status),
                    Text(
                      'Expires ${_formatDate(credential.validUntil)}',
                      style: const TextStyle(color: AnsibleDesign.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  credential.issuerDid,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AnsibleDesign.inkFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: AnsibleDesign.inkMuted,
            tooltip: 'Delete local credential',
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final WalletCredentialStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

Color _statusColor(WalletCredentialStatus status) {
  switch (status) {
    case WalletCredentialStatus.active:
      return const Color(0xFF47D18C);
    case WalletCredentialStatus.expired:
      return const Color(0xFFFFC857);
    case WalletCredentialStatus.revoked:
    case WalletCredentialStatus.suspended:
    case WalletCredentialStatus.deleted:
      return const Color(0xFFFF6B6B);
  }
}

String _statusLabel(WalletCredentialStatus status) {
  switch (status) {
    case WalletCredentialStatus.active:
      return 'Active';
    case WalletCredentialStatus.expired:
      return 'Expired';
    case WalletCredentialStatus.revoked:
      return 'Revoked';
    case WalletCredentialStatus.suspended:
      return 'Suspended';
    case WalletCredentialStatus.deleted:
      return 'Deleted';
  }
}

String _formatDate(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}
