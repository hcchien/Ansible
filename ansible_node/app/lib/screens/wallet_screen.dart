import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../services/external_url_launcher.dart';
import '../services/oid4vp_presentation_service.dart';
import '../services/vc_issuer_client.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import 'credential_issuance_wizard.dart';
import 'wallet_verifier_scanner_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.holderDid,
    required this.repository,
    this.vcIssuerClient,
    this.urlLauncher,
    this.oid4vpPresentationService,
    this.verifierScannerBuilder,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(minutes: 2),
  });

  final String holderDid;
  final WalletRepository repository;
  final VcIssuerClient? vcIssuerClient;
  final ExternalUrlLauncher? urlLauncher;
  final Oid4vpPresentationApprover? oid4vpPresentationService;
  final WidgetBuilder? verifierScannerBuilder;
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

  void _openVerifierScanner() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            widget.verifierScannerBuilder ??
            (_) => WalletVerifierScannerScreen(
              holderDid: widget.holderDid,
              walletRepository: widget.repository,
              presentationService: widget.oid4vpPresentationService,
            ),
      ),
    );
  }

  Future<void> _handleCredentialStored() async {
    if (!mounted) return;
    setState(() => _showWizard = false);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: 'WALLET',
      leadingLabel: text.t('backSettings'),
      trailing: IconButton(
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
        tooltip: text.t('refresh'),
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
              AnsibleMonoLabel(text.t('walletLabel')),
              const SizedBox(height: 6),
              Text(
                text.t('walletHero'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text.t('walletHeroSub'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                text.t('walletHeroBody'),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
              const SizedBox(height: 18),
              _IdentityCard(
                primary: true,
                name: text.t('rootName'),
                en: text.t('rootMeta'),
                type: text.t('rootType'),
                sub: text.t('rootSub'),
                uses: text.t('rootUses'),
                age: text.t('local'),
                keyFragment: _fragment(widget.holderDid),
              ),
              const SizedBox(height: 18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _openAddCredential,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(text.t('addCredential')),
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
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _openVerifierScanner,
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: Text(text.t('scanVerifierRequest')),
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
                ],
              ),
              const SizedBox(height: 16),
              if (_showWizard) ...[
                _buildCredentialWizard(),
                const SizedBox(height: 16),
              ],
              AnsibleMonoLabel(text.t('credentialsLabel')),
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
                child: Text(
                  text.t('walletFooter'),
                  style: const TextStyle(
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
    final text = SubpageL10n.of(context);
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.t('noCredentials'),
                  style: const TextStyle(
                    color: AnsibleDesign.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text.t('noCredentialsSub'),
                  style: const TextStyle(
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
            tooltip: text.t('addCredential'),
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
  });

  final String name;
  final String en;
  final String type;
  final String sub;
  final String uses;
  final String age;
  final String keyFragment;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      child: Text(
                        SubpageL10n.of(context).t('primary'),
                        style: const TextStyle(
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
    );
  }
}

class _CredentialTile extends StatelessWidget {
  const _CredentialTile({required this.credential, required this.onDelete});

  final WalletCredential credential;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
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
                      text.f('expires', {
                        'date': _formatDate(credential.validUntil),
                      }),
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
            tooltip: text.t('deleteLocalCredential'),
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
    final text = SubpageL10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status, text),
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

String _statusLabel(WalletCredentialStatus status, SubpageL10n text) {
  switch (status) {
    case WalletCredentialStatus.active:
      return text.t('statusActive');
    case WalletCredentialStatus.expired:
      return text.t('statusExpired');
    case WalletCredentialStatus.revoked:
      return text.t('statusRevoked');
    case WalletCredentialStatus.suspended:
      return text.t('statusSuspended');
    case WalletCredentialStatus.deleted:
      return text.t('statusDeleted');
  }
}

String _formatDate(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}
