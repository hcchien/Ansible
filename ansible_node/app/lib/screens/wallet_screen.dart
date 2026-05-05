import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import 'tw_provider_credential_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    required this.holderDid,
    required this.repository,
  });

  final String holderDid;
  final WalletRepository repository;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late Future<List<WalletCredential>> _credentials;

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

  Future<void> _openAddCredential() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TwProviderCredentialScreen(holderDid: widget.holderDid),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C1424),
        foregroundColor: Colors.white,
        title: const Text('Wallet'),
        actions: [
          IconButton(
            onPressed: _openAddCredential,
            icon: const Icon(Icons.add),
            tooltip: 'Add credential',
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<WalletCredential>>(
        future: _credentials,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final credentials = snapshot.data ?? const <WalletCredential>[];
          if (credentials.isEmpty) {
            return _EmptyWalletState(onAddCredential: _openAddCredential);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: credentials.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final credential = credentials[index];
              return _CredentialTile(
                credential: credential,
                onDelete: () => _deleteCredential(credential),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyWalletState extends StatelessWidget {
  const _EmptyWalletState({required this.onAddCredential});

  final VoidCallback onAddCredential;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFFFF9F43),
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No credentials yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Verified credentials will appear here after issuance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAddCredential,
              icon: const Icon(Icons.add),
              label: const Text('Add credential'),
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
        color: const Color(0xFF0C1424),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  credential.issuerDid,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: Colors.white70,
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
