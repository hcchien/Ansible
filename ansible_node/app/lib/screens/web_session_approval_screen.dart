import 'package:flutter/material.dart';

import '../services/web_session_approval_client.dart';
import '../services/web_session_grant_service.dart';

typedef WebSessionClock = DateTime Function();

class WebSessionApprovalScreen extends StatefulWidget {
  final String challengeId;
  final String currentDid;
  final WebSessionApprovalGateway? client;
  final WebSessionGrantSigner? grantService;
  final WebSessionDeviceIdProvider? deviceIdProvider;
  final WebSessionClock? now;
  final Duration sessionDuration;
  final ValueChanged<WebSessionApprovalResult>? onApproved;
  final VoidCallback? onRejected;

  const WebSessionApprovalScreen({
    super.key,
    required this.challengeId,
    required this.currentDid,
    this.client,
    this.grantService,
    this.deviceIdProvider,
    this.now,
    this.sessionDuration = const Duration(hours: 12),
    this.onApproved,
    this.onRejected,
  });

  @override
  State<WebSessionApprovalScreen> createState() =>
      _WebSessionApprovalScreenState();
}

class _WebSessionApprovalScreenState extends State<WebSessionApprovalScreen> {
  late final WebSessionApprovalGateway _client;
  late final WebSessionGrantSigner _grantService;
  late final WebSessionDeviceIdProvider _deviceIdProvider;
  late final WebSessionClock _now;
  late final Future<WebSessionChallenge> _challengeFuture;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? WebSessionApprovalClient();
    _grantService = widget.grantService ?? WebSessionGrantService();
    _deviceIdProvider =
        widget.deviceIdProvider ??
        const SecureStorageWebSessionDeviceIdProvider();
    _now = widget.now ?? DateTime.now;
    _challengeFuture = _client.fetchChallenge(widget.challengeId);
  }

  Future<void> _approve(WebSessionChallenge challenge) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final approvingDeviceId = await _deviceIdProvider.getOrCreateDeviceId();
      final now = _now().toUtc();
      final grant = WebSessionGrant(
        challengeId: challenge.challengeId,
        relayOrigin: challenge.relayOrigin,
        webOrigin: challenge.webOrigin,
        subjectDid: widget.currentDid,
        approvingDeviceId: approvingDeviceId,
        scopes: challenge.scopes,
        expiresAt: now.add(widget.sessionDuration),
        createdAt: now,
      );
      final signed = await _grantService.sign(grant);
      final result = await _client.approve(signed);
      if (!mounted) return;
      widget.onApproved?.call(result);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Web session approved.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reject() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _client.reject(widget.challengeId);
      if (!mounted) return;
      widget.onRejected?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Web session rejected.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Approve web session')),
      body: FutureBuilder<WebSessionChallenge>(
        future: _challengeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(message: snapshot.error.toString());
          }
          final challenge = snapshot.requireData;
          return _ApprovalContent(
            challenge: challenge,
            currentDid: widget.currentDid,
            now: _now,
            sessionDuration: widget.sessionDuration,
            submitting: _submitting,
            error: _error,
            onApprove: () => _approve(challenge),
            onReject: _reject,
          );
        },
      ),
    );
  }
}

class _ApprovalContent extends StatelessWidget {
  final WebSessionChallenge challenge;
  final String currentDid;
  final WebSessionClock now;
  final Duration sessionDuration;
  final bool submitting;
  final String? error;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ApprovalContent({
    required this.challenge,
    required this.currentDid,
    required this.now,
    required this.sessionDuration,
    required this.submitting,
    required this.error,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final expired = challenge.isExpired(now());
    final canApprove = !expired && !submitting;
    final sessionExpiresAt = now().toUtc().add(sessionDuration);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'A website is asking to use your app identity.',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        _DetailRow(label: 'Website', value: challenge.webOrigin),
        _DetailRow(label: 'Relay', value: challenge.relayOrigin),
        _DetailRow(label: 'DID', value: currentDid),
        _DetailRow(
          label: 'Request expires',
          value: challenge.expiresAt.toLocal().toIso8601String(),
        ),
        _DetailRow(
          label: 'Session expires',
          value: sessionExpiresAt.toLocal().toIso8601String(),
        ),
        const SizedBox(height: 12),
        const Text('Scopes', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in challenge.scopes) Chip(label: Text(scope)),
          ],
        ),
        if (expired) ...[
          const SizedBox(height: 16),
          const Text(
            'This request has expired.',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: submitting ? null : onReject,
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: canApprove ? onApprove : null,
                child: submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Approve'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
