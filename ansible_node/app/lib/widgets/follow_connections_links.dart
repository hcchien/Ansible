import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import '../l10n/app_l10n.dart';
import '../screens/follow_connections_screen.dart';
import '../services/follow_connections.dart';

class FollowConnectionsLinks extends StatefulWidget {
  const FollowConnectionsLinks({
    super.key,
    required this.db,
    required this.did,
  });
  final AppDatabase db;
  final String did;
  @override
  State<FollowConnectionsLinks> createState() => _FollowConnectionsLinksState();
}

class _FollowConnectionsLinksState extends State<FollowConnectionsLinks> {
  late Future<FollowConnections> _data;
  @override
  void initState() {
    super.initState();
    _data = loadFollowConnections(widget.db, widget.did);
  }

  @override
  void didUpdateWidget(covariant FollowConnectionsLinks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.did != widget.did || oldWidget.db != widget.db) {
      _data = loadFollowConnections(widget.db, widget.did);
    }
  }

  Future<void> _open(int tab) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowConnectionsScreen(
          db: widget.db,
          did: widget.did,
          initialTab: tab,
        ),
      ),
    );
    if (mounted) {
      setState(() => _data = loadFollowConnections(widget.db, widget.did));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FollowConnections>(
    future: _data,
    builder: (context, snapshot) {
      final current = snapshot.connectionState == ConnectionState.done
          ? snapshot.data
          : null;
      final following = current?.followingCount;
      final followers = current?.followerCount;
      return Wrap(
        spacing: 12,
        children: [
          TextButton(
            key: const Key('open_following'),
            onPressed: () => _open(0),
            child: Text(
              context.uiCopy(
                zh: '${following ?? '—'} 追蹤中',
                en: '${following ?? '—'} Following',
              ),
            ),
          ),
          TextButton(
            key: const Key('open_followers'),
            onPressed: () => _open(1),
            child: Text(
              context.uiCopy(
                zh: '${followers ?? '—'} 追蹤者',
                en: '${followers ?? '—'} Followers',
              ),
            ),
          ),
        ],
      );
    },
  );
}
