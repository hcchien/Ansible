import 'package:flutter/material.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import '../l10n/subpage_l10n.dart';
import '../services/content_publication_service.dart';
import '../services/app_sync_service.dart';
import '../services/nostr_publication_service.dart';
import '../services/nostr_relay_settings_store.dart';
import '../services/nostr_secure_key_store.dart';
import '../widgets/remote_node_form_dialog.dart';
import '../services/remote_sync_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/nostr_publication_retry_panel.dart';
import '../widgets/nostr_relay_settings_panel.dart';

class SyncSettingsScreen extends StatefulWidget {
  final AppDatabase db;

  const SyncSettingsScreen({super.key, required this.db});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  static const int _retainForeverValue = 0;
  static const List<int> _retentionOptions = [
    7,
    30,
    90,
    180,
    365,
    _retainForeverValue,
  ];

  late final DriftRemoteNodeRepository _remoteNodeRepo;
  late final DriftBoardSyncConfigRepository _boardSyncConfigRepo;
  late final DriftHostedBoardRepository _hostedBoardRepo;
  late final DriftBoardRepository _boardRepo;
  late final DriftThreadRepository _threadRepo;
  late final DriftPostRepository _postRepo;
  late final DriftContentItemRepository _contentItemRepo;
  late final DriftPublicationRepository _publicationRepo;
  late final SecureStorageNostrKeyStore _nostrKeyStore;
  late final SecureStorageNostrRelaySettingsStore _nostrRelaySettingsStore;

  List<RemoteNode> _remoteNodes = [];
  List<Board> _boards = [];
  List<NostrRelayPreference> _nostrRelays = [];
  List<PublicationTarget> _failedNostrTargets = [];
  Map<String, Map<String, bool>> _boardSyncStatusByNode =
      {}; // nodeId -> {boardId -> enabled}
  Map<String, Map<String, int?>> _boardRetentionByNode =
      {}; // nodeId -> {boardId -> days, null -> forever}
  bool _isLoading = true;
  final Map<String, bool> _syncingNodes = {}; // nodeId -> isSyncing
  String? _expandedNodeId;

  @override
  void initState() {
    super.initState();
    _remoteNodeRepo = DriftRemoteNodeRepository(widget.db);
    _boardSyncConfigRepo = DriftBoardSyncConfigRepository(widget.db);
    _hostedBoardRepo = DriftHostedBoardRepository(widget.db);
    _boardRepo = DriftBoardRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _contentItemRepo = DriftContentItemRepository(widget.db);
    _publicationRepo = DriftPublicationRepository(widget.db);
    _nostrKeyStore = const SecureStorageNostrKeyStore();
    _nostrRelaySettingsStore = const SecureStorageNostrRelaySettingsStore();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final nodes = await _remoteNodeRepo.list();
      final boards = await _boardRepo.list();
      final nostrRelays = await _nostrRelaySettingsStore.list();
      final failedNostrTargets = await _publicationRepo.listTargets(
        protocol: PublicationProtocol.nostr,
        status: PublicationStatus.failed,
      );

      Map<String, Map<String, bool>> syncStatusByNode = {};
      Map<String, Map<String, int?>> retentionByNode = {};
      for (final node in nodes) {
        final configs = await _boardSyncConfigRepo.listByRemote(node.id);
        syncStatusByNode[node.id] = {};
        retentionByNode[node.id] = {};
        for (final config in configs) {
          syncStatusByNode[node.id]![config.boardId] = config.syncEnabled;
          retentionByNode[node.id]![config.boardId] = config.retentionDays;
        }
      }

      setState(() {
        _remoteNodes = nodes;
        _boards = boards.where((b) => !b.isDeleted).toList();
        _nostrRelays = nostrRelays;
        _failedNostrTargets = failedNostrTargets;
        _boardSyncStatusByNode = syncStatusByNode;
        _boardRetentionByNode = retentionByNode;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        final text = SubpageL10n.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text.f('loadError', {'error': e}))),
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
      builder: (context) =>
          RemoteNodeFormDialog(initialName: node.name, initialUrl: node.url),
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
        final response = await client.login(
          data['username']!,
          data['password']!,
        );
        accessToken = response['access_token'] as String?;
      } catch (e) {
        if (mounted) {
          final text = SubpageL10n.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(text.f('authFailed', {'error': e}))),
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
      final text = SubpageL10n.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t('forumHostAdded'))));
    }
  }

  Future<void> _updateRemoteNode(
    RemoteNode node,
    Map<String, String?> data,
  ) async {
    String? accessToken = node.accessToken;

    // If new credentials provided, try to authenticate
    if (data['username'] != null && data['password'] != null) {
      try {
        final client = RelayApiClient(baseUrl: data['url']!);
        final response = await client.login(
          data['username']!,
          data['password']!,
        );
        accessToken = response['access_token'] as String?;
      } catch (e) {
        if (mounted) {
          final text = SubpageL10n.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(text.f('authFailed', {'error': e}))),
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
      final text = SubpageL10n.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t('forumHostUpdated'))));
    }
  }

  Future<void> _deleteRemoteNode(RemoteNode node) async {
    final text = SubpageL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.t('deleteForumHostTitle')),
        content: Text(text.f('deleteForumHostConfirm', {'name': node.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(MaterialLocalizations.of(context).deleteButtonTooltip),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _remoteNodeRepo.delete(node.id);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text.t('forumHostDeleted'))));
      }
    }
  }

  Future<void> _toggleBoardSync(
    String nodeId,
    String boardId,
    bool enabled,
  ) async {
    await _boardSyncConfigRepo.toggleSync(nodeId, boardId, enabled);
    setState(() {
      _boardSyncStatusByNode[nodeId] ??= {};
      _boardRetentionByNode[nodeId] ??= {};
      _boardSyncStatusByNode[nodeId]![boardId] = enabled;
      _boardRetentionByNode[nodeId]![boardId] ??=
          BoardSyncConfig.defaultRetentionDays;
    });
  }

  Future<void> _updateBoardRetention(
    String nodeId,
    String boardId,
    int? retentionDays,
  ) async {
    final existing = await _boardSyncConfigRepo.getByRemoteAndBoard(
      nodeId,
      boardId,
    );
    final now = DateTime.now();

    if (existing == null) {
      await _boardSyncConfigRepo.create(
        BoardSyncConfig(
          id: '${nodeId}_$boardId',
          remoteNodeId: nodeId,
          boardId: boardId,
          syncEnabled: false,
          retentionDays: retentionDays,
          createdAt: now,
          updatedAt: now,
        ),
      );
    } else {
      await _boardSyncConfigRepo.update(
        existing.copyWith(retentionDays: retentionDays, updatedAt: now),
      );
    }

    setState(() {
      _boardRetentionByNode[nodeId] ??= {};
      _boardRetentionByNode[nodeId]![boardId] = retentionDays;
    });
  }

  Future<SyncResult> _performSync(
    RemoteNode node, {
    bool showSnackBar = true,
    bool publishPublicContent = true,
  }) async {
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
        hostedBoardRepo: _hostedBoardRepo,
        boardRepo: _boardRepo,
        threadRepo: _threadRepo,
        postRepo: _postRepo,
      );

      final result = await syncService.syncFromNode(client, node);
      final publishSummary = publishPublicContent
          ? await bestEffortPublicPublish(
              () => _publishPublicContent(showSnackBar: false),
            )
          : const PublicPublishSummary(publicItems: 0);

      setState(() {
        _syncingNodes[node.id] = false;
      });

      // Reload to update last sync time
      await _loadData();

      if (mounted && showSnackBar) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${node.name}: pull ${result.activitiesProcessed} activities；${_publishSummaryMessage(publishSummary)}',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${node.name}: Sync failed - ${result.errorMessage}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return result;
    } catch (e) {
      setState(() {
        _syncingNodes[node.id] = false;
      });

      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${node.name}: Sync error - $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return SyncResult.failure(errorMessage: e.toString());
    }
  }

  Future<void> _syncAllNodes() async {
    var pulledActivities = 0;
    final pullErrors = <String>[];
    for (final node in _remoteNodes) {
      if (node.isActive) {
        final result = await _performSync(
          node,
          showSnackBar: false,
          publishPublicContent: false,
        );
        if (result.success) {
          pulledActivities += result.activitiesProcessed;
        } else {
          pullErrors.add('${node.name}: ${result.errorMessage}');
        }
      }
    }
    final publishSummary = await bestEffortPublicPublish(
      () => _publishPublicContent(showSnackBar: false),
    );
    if (!mounted) return;
    final message = _syncAllSummaryMessage(
      pulledActivities: pulledActivities,
      pullErrors: pullErrors,
      publishSummary: publishSummary,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<PublicPublishSummary> _publishPublicContent({
    bool showSnackBar = true,
  }) async {
    final publicItems = (await _contentItemRepo.list())
        .where((item) => item.visibility != ContentVisibility.private)
        .toList();
    if (publicItems.isEmpty) {
      return const PublicPublishSummary(publicItems: 0);
    }
    final distributionPreference = _configuredDistributionPreference();
    if (distributionPreference == DistributionPreference.localOnly) {
      return PublicPublishSummary(
        publicItems: publicItems.length,
        skipped: publicItems.length,
        skippedReasons: const {'localOnly'},
      );
    }

    final service = ContentPublicationService(
      contentItems: _contentItemRepo,
      publications: _publicationRepo,
      relaySettings: _nostrRelaySettingsStore,
      remoteNodes: _remoteNodeRepo,
      keyStore: _nostrKeyStore,
      signingBridge: const SchnorrSigningBridge(),
    );
    var published = 0;
    var failed = 0;
    var enqueued = 0;
    var skipped = 0;
    final skippedReasons = <String>{};
    final failureReasons = <String>{};
    for (final item in publicItems) {
      final result = await service.publishContentItem(
        item,
        distributionPreference: distributionPreference,
      );
      published += result.published;
      failed += result.failed;
      enqueued += result.enqueued;
      failureReasons.addAll(result.errors);
      if (result.enqueued == 0 && result.published == 0 && result.failed == 0) {
        skipped++;
        if (result.skippedReason != null) {
          skippedReasons.add(result.skippedReason!);
        }
      }
    }
    await _loadData();
    final summary = PublicPublishSummary(
      publicItems: publicItems.length,
      enqueued: enqueued,
      published: published,
      failed: failed,
      skipped: skipped,
      skippedReasons: skippedReasons,
      failureReasons: failureReasons,
    );
    if (!mounted || !showSnackBar) return summary;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_publishSummaryMessage(summary))));
    return summary;
  }

  String _syncAllSummaryMessage({
    required int pulledActivities,
    required List<String> pullErrors,
    required PublicPublishSummary publishSummary,
  }) {
    return appSyncSummaryMessage(
      AppSyncResult(
        pulledActivities: pulledActivities,
        pullErrors: pullErrors,
        publishSummary: publishSummary,
      ),
    );
  }

  String _publishSummaryMessage(PublicPublishSummary summary) {
    return publicPublishSummaryMessage(summary);
  }

  DistributionPreference _configuredDistributionPreference() {
    final hasNostr = _nostrRelays.any((relay) => relay.write);
    final hasRelay = _remoteNodes.any((node) => node.isActive);
    if (hasNostr && hasRelay) return DistributionPreference.nostrAndActivityPub;
    if (hasNostr) return DistributionPreference.nostr;
    if (hasRelay) return DistributionPreference.activityPub;
    return DistributionPreference.localOnly;
  }

  Future<void> _retryNostrTarget(PublicationTarget target) async {
    final service = NostrPublicationService(
      contentItems: _contentItemRepo,
      publications: _publicationRepo,
      keyStore: _nostrKeyStore,
      signer: ProductionNostrEventSigner(
        keyStore: _nostrKeyStore,
        signingBridge: const SchnorrSigningBridge(),
      ),
    );
    final result = await service.retryTarget(target.targetId);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.published > 0
              ? SubpageL10n.of(context).t('nostrRetrySuccess')
              : SubpageL10n.of(context).t('nostrRetryFailed'),
        ),
      ),
    );
  }

  Future<void> _resetNostrTarget(PublicationTarget target) async {
    await _publicationRepo.resetTargetForRetry(target.targetId);
    await _loadData();
    if (!mounted) return;
    final text = SubpageL10n.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('nostrResetDone'))));
  }

  Future<void> _updateNostrRelays(List<NostrRelayPreference> relays) async {
    await _nostrRelaySettingsStore.save(relays);
    final normalized = await _nostrRelaySettingsStore.list();
    if (!mounted) return;
    setState(() => _nostrRelays = normalized);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = SubpageL10n.of(context);
    final hasSyncTargets =
        _remoteNodes.isNotEmpty || _nostrRelays.any((relay) => relay.write);

    return AnsibleScreenScaffold(
      title: 'SYNC',
      leadingLabel: text.t('backSettings'),
      trailing: IconButton(
        onPressed: !hasSyncTargets || _syncingNodes.values.any((v) => v)
            ? null
            : _syncAllNodes,
        icon: const Icon(Icons.sync),
        tooltip: text.t('syncAll'),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnsibleMonoLabel(text.t('syncLabel')),
                      const SizedBox(height: 6),
                      Text(
                        text.t('peerNoCloud'),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AnsibleDesign.paperDeep.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AnsibleMark(
                              size: 18,
                              color: AnsibleDesign.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                text.t('syncHeroDescription'),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.6,
                                  color: AnsibleDesign.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AnsibleMonoLabel(
                  text.t('forumHosts'),
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                ),
                if (_remoteNodes.isEmpty)
                  _buildEmptyState(theme)
                else
                  AnsibleRuleGroup(
                    children: [
                      for (var i = 0; i < _remoteNodes.length; i += 1)
                        _buildServerCard(_remoteNodes[i], theme),
                    ],
                  ),
                AnsibleMonoLabel(
                  text.t('syncedCircles'),
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                ),
                AnsibleRuleGroup(
                  children: [
                    for (var i = 0; i < _boards.take(3).length; i += 1)
                      _CircleSyncRow(
                        name: _boards[i].title,
                        subtitle: text.t('hostedBoardProjection'),
                        status: i == 2
                            ? _CircleSyncStatus.paused
                            : _CircleSyncStatus.live,
                      ),
                    if (_boards.isEmpty) const _EmptyCircleSyncRow(),
                  ],
                ),
                NostrPublicationRetryPanel(
                  failedTargets: _failedNostrTargets,
                  onRetry: _retryNostrTarget,
                  onReset: _resetNostrTarget,
                ),
                NostrRelaySettingsPanel(
                  relays: _nostrRelays,
                  onChanged: _updateNostrRelays,
                ),
                AnsibleMonoLabel(
                  text.t('advanced'),
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                ),
                AnsibleRuleGroup(
                  children: [
                    _SyncSwitchRow(
                      label: text.t('wifiOnly'),
                      sub: text.t('wifiOnlySub'),
                      on: true,
                    ),
                    _SyncSwitchRow(
                      label: text.t('largeAttachments'),
                      sub: text.t('largeAttachmentsSub'),
                      on: false,
                    ),
                    _SyncSwitchRow(
                      label: text.t('backgroundSync'),
                      sub: text.t('backgroundSyncSub'),
                      on: true,
                      last: true,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                  child: Text(
                    text.t('syncEncryptedFooter'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: AnsibleDesign.inkFaint,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final text = SubpageL10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AnsibleDesign.paperElev,
              border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const AnsibleGlyphBox(glyph: '↔'),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text.t('noForumHost'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AnsibleDesign.inkMuted,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showAddRemoteNodeDialog,
            icon: const Icon(Icons.add),
            label: Text(text.t('addForumHost')),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard(RemoteNode node, ThemeData theme) {
    final text = SubpageL10n.of(context);
    final isExpanded = _expandedNodeId == node.id;
    final isSyncing = _syncingNodes[node.id] ?? false;
    final boardSyncStatus = _boardSyncStatusByNode[node.id] ?? {};
    final boardRetention = _boardRetentionByNode[node.id] ?? {};
    final enabledCount = boardSyncStatus.values.where((v) => v).length;

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
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
                      color: node.isActive
                          ? AnsibleDesign.spore
                          : AnsibleDesign.inkFaint,
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
                            color: AnsibleDesign.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          node.url,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AnsibleDesign.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.sync,
                              size: 14,
                              color: AnsibleDesign.inkFaint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              node.lastSyncAt != null
                                  ? text.f('lastSync', {
                                      'time': _formatDateTime(node.lastSyncAt!),
                                    })
                                  : text.t('neverSynced'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AnsibleDesign.inkFaint,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(
                              Icons.dashboard,
                              size: 14,
                              color: AnsibleDesign.inkFaint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              enabledCount > 0
                                  ? text.f('hostedBoardsSelected', {
                                      'count': enabledCount,
                                    })
                                  : text.t('noHostedBoardsSelected'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AnsibleDesign.inkFaint,
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
                    tooltip: text.t('syncNow'),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AnsibleDesign.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1, color: AnsibleDesign.ruleSoft),
            // Board selection
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        text.t('hostedBoards'),
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
                        child: Text(text.t('selectAll')),
                      ),
                      TextButton(
                        onPressed: () async {
                          // Clear all
                          for (final board in _boards) {
                            await _toggleBoardSync(node.id, board.id, false);
                          }
                        },
                        child: Text(text.t('clearAll')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text.t('hostedBoardsDescription'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_boards.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        text.t('noHostedBoardsAvailable'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AnsibleDesign.inkMuted,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: _boards.map((board) {
                        final isEnabled = boardSyncStatus[board.id] ?? false;
                        final retentionDays =
                            boardRetention.containsKey(board.id)
                            ? boardRetention[board.id]
                            : BoardSyncConfig.defaultRetentionDays;
                        final retentionValue =
                            retentionDays ?? _retainForeverValue;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  value: isEnabled,
                                  onChanged: (selected) {
                                    _toggleBoardSync(
                                      node.id,
                                      board.id,
                                      selected ?? false,
                                    );
                                  },
                                  title: Text(board.title),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 132,
                                child: DropdownButtonFormField<int>(
                                  initialValue: retentionValue,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: null,
                                  ),
                                  items: _retentionOptions
                                      .map(
                                        (days) => DropdownMenuItem<int>(
                                          value: days,
                                          child: Text(
                                            _formatRetention(days, text),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (days) {
                                    _updateBoardRetention(
                                      node.id,
                                      board.id,
                                      days == _retainForeverValue ? null : days,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AnsibleDesign.ruleSoft),
            // Server actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showEditRemoteNodeDialog(node),
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text(SubpageL10n.of(context).t('editRemoteNode')),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteRemoteNode(node),
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    label: Text(
                      MaterialLocalizations.of(context).deleteButtonTooltip,
                      style: const TextStyle(color: Colors.red),
                    ),
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

  static String _formatRetention(int days, SubpageL10n text) {
    return days == _retainForeverValue
        ? text.t('forever')
        : text.f('daysShort', {'count': days});
  }
}

enum _CircleSyncStatus { live, paused, behind }

class _EmptyCircleSyncRow extends StatelessWidget {
  const _EmptyCircleSyncRow();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Text(
        text.t('noSyncedCircles'),
        style: const TextStyle(
          fontSize: 13,
          height: 1.6,
          color: AnsibleDesign.inkMuted,
        ),
      ),
    );
  }
}

class _CircleSyncRow extends StatelessWidget {
  const _CircleSyncRow({
    required this.name,
    required this.subtitle,
    required this.status,
  });

  final String name;
  final String subtitle;
  final _CircleSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _CircleSyncStatus.live => AnsibleDesign.spore,
      _CircleSyncStatus.paused => AnsibleDesign.rule,
      _CircleSyncStatus.behind => AnsibleDesign.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AnsibleDesign.paperDeep,
              border: Border.all(color: AnsibleDesign.rule, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Text(
              name.characters.first,
              style: const TextStyle(
                fontSize: 11,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }
}

class _SyncSwitchRow extends StatelessWidget {
  const _SyncSwitchRow({
    required this.label,
    required this.sub,
    required this.on,
    this.last = false,
  });

  final String label;
  final String sub;
  final bool on;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: last
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: on, onChanged: null),
        ],
      ),
    );
  }
}
