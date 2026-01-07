import 'package:flutter/material.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import '../widgets/remote_node_form_dialog.dart';
import '../services/remote_sync_service.dart';

class SyncSettingsScreen extends StatefulWidget {
  final AppDatabase db;

  const SyncSettingsScreen({
    super.key,
    required this.db,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  late final DriftRemoteNodeRepository _remoteNodeRepo;
  late final DriftBoardSyncConfigRepository _boardSyncConfigRepo;
  late final DriftBoardRepository _boardRepo;
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;

  List<RemoteNode> _remoteNodes = [];
  List<Board> _boards = [];
  Map<String, Map<String, bool>> _boardSyncStatusByNode = {}; // nodeId -> {boardId -> enabled}
  bool _isLoading = true;
  Map<String, bool> _syncingNodes = {}; // nodeId -> isSyncing
  String? _expandedNodeId;

  @override
  void initState() {
    super.initState();
    _remoteNodeRepo = DriftRemoteNodeRepository(widget.db);
    _boardSyncConfigRepo = DriftBoardSyncConfigRepository(widget.db);
    _boardRepo = DriftBoardRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final nodes = await _remoteNodeRepo.list();
      final boards = await _boardRepo.list();

      Map<String, Map<String, bool>> syncStatusByNode = {};
      for (final node in nodes) {
        final configs = await _boardSyncConfigRepo.listByRemote(node.id);
        syncStatusByNode[node.id] = {};
        for (final config in configs) {
          syncStatusByNode[node.id]![config.boardId] = config.syncEnabled;
        }
      }

      setState(() {
        _remoteNodes = nodes;
        _boards = boards.where((b) => !b.isDeleted).toList();
        _boardSyncStatusByNode = syncStatusByNode;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _showAddRemoteNodeDialog() async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => const RemoteNodeFormDialog(),
    );

    if (result != null) {
      await _saveRemoteNode(result);
    }
  }

  Future<void> _showEditRemoteNodeDialog(RemoteNode node) async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => RemoteNodeFormDialog(
        initialName: node.name,
        initialUrl: node.url,
      ),
    );

    if (result != null) {
      await _updateRemoteNode(node, result);
    }
  }

  Future<void> _saveRemoteNode(Map<String, String?> data) async {
    final now = DateTime.now();
    String? accessToken;

    // If credentials provided, try to authenticate
    if (data['username'] != null && data['password'] != null) {
      try {
        final client = RelayApiClient(baseUrl: data['url']!);
        final response = await client.login(data['username']!, data['password']!);
        accessToken = response['access_token'] as String?;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Authentication failed: $e')),
          );
        }
        return;
      }
    }

    final node = RemoteNode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: data['name']!,
      url: data['url']!,
      accessToken: accessToken,
      createdAt: now,
      updatedAt: now,
      isActive: true,
    );

    await _remoteNodeRepo.create(node);
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server added')),
      );
    }
  }

  Future<void> _updateRemoteNode(RemoteNode node, Map<String, String?> data) async {
    String? accessToken = node.accessToken;

    // If new credentials provided, try to authenticate
    if (data['username'] != null && data['password'] != null) {
      try {
        final client = RelayApiClient(baseUrl: data['url']!);
        final response = await client.login(data['username']!, data['password']!);
        accessToken = response['access_token'] as String?;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Authentication failed: $e')),
          );
        }
        return;
      }
    }

    final updated = node.copyWith(
      name: data['name'],
      url: data['url'],
      accessToken: accessToken,
      updatedAt: DateTime.now(),
    );

    await _remoteNodeRepo.update(updated);
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server updated')),
      );
    }
  }

  Future<void> _deleteRemoteNode(RemoteNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Are you sure you want to delete "${node.name}"?\n\nThis will also remove all board sync settings for this server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _remoteNodeRepo.delete(node.id);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server deleted')),
        );
      }
    }
  }

  Future<void> _toggleBoardSync(String nodeId, String boardId, bool enabled) async {
    await _boardSyncConfigRepo.toggleSync(nodeId, boardId, enabled);
    setState(() {
      _boardSyncStatusByNode[nodeId] ??= {};
      _boardSyncStatusByNode[nodeId]![boardId] = enabled;
    });
  }

  Future<void> _performSync(RemoteNode node) async {
    setState(() {
      _syncingNodes[node.id] = true;
    });

    try {
      final client = RelayApiClient(baseUrl: node.url);
      if (node.accessToken != null) {
        client.setAccessToken(node.accessToken);
      }

      final syncService = RemoteSyncService(
        remoteNodeRepo: _remoteNodeRepo,
        boardSyncConfigRepo: _boardSyncConfigRepo,
        boardRepo: _boardRepo,
        threadRepo: _threadRepo,
        postRepo: _postRepo,
      );

      final result = await syncService.syncFromNode(client, node);

      setState(() {
        _syncingNodes[node.id] = false;
      });

      // Reload to update last sync time
      await _loadData();

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${node.name}: Synced ${result.activitiesProcessed} activities'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${node.name}: Sync failed - ${result.errorMessage}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _syncingNodes[node.id] = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${node.name}: Sync error - $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _syncAllNodes() async {
    for (final node in _remoteNodes) {
      if (node.isActive) {
        await _performSync(node);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Settings'),
        actions: [
          if (_remoteNodes.isNotEmpty)
            TextButton.icon(
              onPressed: _syncingNodes.values.any((v) => v) ? null : _syncAllNodes,
              icon: const Icon(Icons.sync),
              label: const Text('Sync All'),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRemoteNodeDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Server'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _remoteNodes.isEmpty
              ? _buildEmptyState(theme)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _remoteNodes.length,
                  itemBuilder: (context, index) {
                    final node = _remoteNodes[index];
                    return _buildServerCard(node, theme);
                  },
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No sync servers configured',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a server to start syncing boards',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _showAddRemoteNodeDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Server'),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(RemoteNode node, ThemeData theme) {
    final isExpanded = _expandedNodeId == node.id;
    final isSyncing = _syncingNodes[node.id] ?? false;
    final boardSyncStatus = _boardSyncStatusByNode[node.id] ?? {};
    final enabledCount = boardSyncStatus.values.where((v) => v).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          // Server Header
          InkWell(
            onTap: () {
              setState(() {
                _expandedNodeId = isExpanded ? null : node.id;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Status indicator
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: node.isActive ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Server info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          node.url,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.sync,
                              size: 14,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              node.lastSyncAt != null
                                  ? 'Last: ${_formatDateTime(node.lastSyncAt!)}'
                                  : 'Never synced',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white54,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(
                              Icons.dashboard,
                              size: 14,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              enabledCount > 0
                                  ? '$enabledCount boards selected'
                                  : 'All boards',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  IconButton(
                    onPressed: isSyncing ? null : () => _performSync(node),
                    icon: isSyncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    tooltip: 'Sync now',
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            // Board selection
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Boards to Sync',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          // Select all
                          for (final board in _boards) {
                            await _toggleBoardSync(node.id, board.id, true);
                          }
                        },
                        child: const Text('Select All'),
                      ),
                      TextButton(
                        onPressed: () async {
                          // Clear all
                          for (final board in _boards) {
                            await _toggleBoardSync(node.id, board.id, false);
                          }
                        },
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select specific boards to sync, or leave all unchecked to sync everything.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_boards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No boards available',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _boards.map((board) {
                        final isEnabled = boardSyncStatus[board.id] ?? false;
                        return FilterChip(
                          label: Text(board.title),
                          selected: isEnabled,
                          onSelected: (selected) {
                            _toggleBoardSync(node.id, board.id, selected);
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
            // Server actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showEditRemoteNodeDialog(node),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteRemoteNode(node),
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
