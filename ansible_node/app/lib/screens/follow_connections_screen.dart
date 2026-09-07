import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import '../l10n/app_l10n.dart';
import '../services/follow_connections.dart';
import 'user_profile_screen.dart';

class FollowConnectionsScreen extends StatefulWidget {
  const FollowConnectionsScreen({
    super.key,
    required this.db,
    required this.did,
    this.initialTab = 0,
  });
  final AppDatabase db;
  final String did;
  final int initialTab;
  @override
  State<FollowConnectionsScreen> createState() =>
      _FollowConnectionsScreenState();
}

class _FollowConnectionsScreenState extends State<FollowConnectionsScreen> {
  late Future<FollowConnections> _data;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _data = loadFollowConnections(widget.db, widget.did);
  }

  Future<void> _reload() async {
    final future = loadFollowConnections(widget.db, widget.did);
    setState(() => _data = future);
    try {
      await future;
    } catch (_) {
      /* FutureBuilder presents retry. */
    }
  }

  @override
  void didUpdateWidget(covariant FollowConnectionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.did != widget.did || oldWidget.db != widget.db) {
      _data = loadFollowConnections(widget.db, widget.did);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: widget.initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.uiCopy(zh: '我的追蹤關係', en: 'My connections')),
        actions: [
          IconButton(
            tooltip: context.uiCopy(zh: '重新整理', en: 'Refresh'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: FutureBuilder<FollowConnections>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.uiCopy(
                          zh: '無法讀取追蹤清單',
                          en: 'Could not load connections',
                        ),
                      ),
                      TextButton(
                        onPressed: _reload,
                        child: Text(context.uiCopy(zh: '重試', en: 'Retry')),
                      ),
                    ],
                  ),
                );
              }
              final data = snapshot.connectionState == ConnectionState.done
                  ? snapshot.data
                  : null;
              if (data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(
                        text: context.uiCopy(
                          zh: '追蹤中 ${data.followingCount}',
                          en: 'Following ${data.followingCount}',
                        ),
                      ),
                      Tab(
                        text: context.uiCopy(
                          zh: '追蹤者 ${data.followerCount}',
                          en: 'Followers ${data.followerCount}',
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      key: const Key('connections_search'),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: context.uiCopy(
                          zh: '搜尋名稱、handle 或 DID',
                          en: 'Search name, handle or DID',
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.uiCopy(
                        zh: '顯示這台裝置已知的關係；其他裝置的變更需同步後更新。待核准請求不計入人數。',
                        en: 'Relationships known to this device. Sync to receive changes from other devices. Pending requests are not counted.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _list(data.following, false),
                        _list(data.followers, true),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget _list(List<FollowConnection> all, bool followers) {
    final items = all
        .where(
          (p) => '${p.name} ${p.handle ?? ''} ${p.did}'.toLowerCase().contains(
            _query,
          ),
        )
        .toList();
    final accepted = items.where((p) => !p.pending).toList();
    final pending = items.where((p) => p.pending).toList();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _query.isNotEmpty
                    ? context.uiCopy(zh: '沒有符合的使用者', en: 'No matching people')
                    : followers
                    ? context.uiCopy(zh: '目前沒有追蹤者', en: 'No followers yet')
                    : context.uiCopy(
                        zh: '目前沒有追蹤任何人',
                        en: 'You are not following anyone yet',
                      ),
                textAlign: TextAlign.center,
              ),
            ),
          for (final person in accepted) _person(person),
          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                followers
                    ? context.uiCopy(
                        zh: '等待你核准 ${pending.length}',
                        en: 'Awaiting your approval ${pending.length}',
                      )
                    : context.uiCopy(
                        zh: '等待對方核准 ${pending.length}',
                        en: 'Requested ${pending.length}',
                      ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          for (final person in pending) _person(person),
        ],
      ),
    );
  }

  Widget _person(FollowConnection person) => ListTile(
    key: ValueKey('connection_${person.edge.direction.name}_${person.did}'),
    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
    title: Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        if (person.handle?.isNotEmpty == true) person.handle!,
        person.did,
        if (person.localOnly)
          context.uiCopy(zh: '只在此裝置追蹤', en: 'Following only on this device'),
      ].join('\n'),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(
            db: widget.db,
            followerDid: widget.did,
            did: person.did,
            displayName: person.name,
          ),
        ),
      );
      if (mounted) await _reload();
    },
  );
}
