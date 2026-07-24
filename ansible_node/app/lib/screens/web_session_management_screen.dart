import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/web_session_approval_client.dart';

typedef WebSessionManagementClock = DateTime Function();

class WebSessionManagementScreen extends StatefulWidget {
  final String bearerToken;
  final WebSessionApprovalGateway? client;
  final WebSessionManagementClock? now;

  const WebSessionManagementScreen({
    super.key,
    required this.bearerToken,
    this.client,
    this.now,
  });

  @override
  State<WebSessionManagementScreen> createState() =>
      _WebSessionManagementScreenState();
}

class _WebSessionManagementScreenState
    extends State<WebSessionManagementScreen> {
  late final WebSessionApprovalGateway _client;
  late final WebSessionManagementClock _now;
  late Future<List<WebSessionRecord>> _sessionsFuture;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? WebSessionApprovalClient();
    _now = widget.now ?? DateTime.now;
    _sessionsFuture = _loadSessions();
  }

  Future<List<WebSessionRecord>> _loadSessions() {
    return _client.fetchSessions(widget.bearerToken);
  }

  Future<void> _revoke(WebSessionRecord session) async {
    setState(() => _error = null);
    try {
      await _client.revokeSession(
        bearerToken: widget.bearerToken,
        sessionId: session.sessionId,
      );
      setState(() => _sessionsFuture = _loadSessions());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(zh: '網頁工作階段已撤銷。', en: 'Web session revoked.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.uiCopy(zh: '網頁工作階段', en: 'Web sessions')),
      ),
      body: FutureBuilder<List<WebSessionRecord>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _MessageState(message: snapshot.error.toString());
          }
          final sessions = snapshot.data ?? const [];
          if (sessions.isEmpty) {
            return _MessageState(
              message: context.uiCopy(
                zh: '沒有使用中的網頁工作階段。',
                en: 'No active web sessions.',
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length + (_error == null ? 0 : 1),
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (_error != null && index == 0) {
                return Text(_error!, style: const TextStyle(color: Colors.red));
              }
              final session = sessions[index - (_error == null ? 0 : 1)];
              return _WebSessionTile(
                session: session,
                isExpired: session.isExpired(_now()),
                onRevoke: () => _revoke(session),
              );
            },
          );
        },
      ),
    );
  }
}

class _WebSessionTile extends StatelessWidget {
  final WebSessionRecord session;
  final bool isExpired;
  final VoidCallback onRevoke;

  const _WebSessionTile({
    required this.session,
    required this.isExpired,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(session.webOrigin),
      subtitle: Text(
        [
          session.approvingDeviceId,
          session.trustTier,
          'Expires ${session.expiresAt.toLocal().toIso8601String()}',
          session.sessionId,
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: TextButton(
        onPressed: isExpired ? null : onRevoke,
        child: Text(context.uiCopy(zh: '撤銷', en: 'Revoke')),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;

  const _MessageState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}
