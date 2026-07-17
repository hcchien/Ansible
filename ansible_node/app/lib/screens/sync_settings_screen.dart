import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../services/content_publication_service.dart';
import '../services/relay_discovery_client.dart';
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

part 'sync_settings_screen.rows.dart';

/// Whether adding a host with this self-declared compliance level needs an
/// explicit user confirmation first. Only the two levels that positively
/// declare constitution compatibility add silently; unknown/undeclared,
/// non-compliant, and any unrecognised future value warn first. The level
/// stays display/ranking input only — never trust-bearing (constitution
/// "Scope And Compliance").
bool hostComplianceNeedsWarning(String? compliance) {
  return compliance != 'constitution_compliant' && compliance != 'compatible';
}

class SyncSettingsScreen extends StatefulWidget {
  final AppDatabase db;
  final String localDid;
  final String? initialForumHostUrl;

  /// Test seam for fetching a host's self-declared constitution compliance
  /// at add time. Defaults to [RelayDiscoveryClient] against the host URL.
  final Future<String?> Function(String url)? complianceFetcher;

  const SyncSettingsScreen({
    super.key,
    required this.db,
    required this.localDid,
    this.initialForumHostUrl,
    this.complianceFetcher,
  });

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
  bool _shownInitialForumHostDialog = false;
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
      final hostedSubscriptions = await _hostedBoardRepo.listSubscriptions();
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
      // Hosted subscriptions are the authoritative sync switch for Forum Host
      // boards. Overlay them on legacy configs so the checkbox reflects what
      // RemoteSyncService actually reads.
      for (final subscription in hostedSubscriptions) {
        syncStatusByNode[subscription.forumHostId] ??= {};
        retentionByNode[subscription.forumHostId] ??= {};
        syncStatusByNode[subscription.forumHostId]![subscription.localBoardId] =
            subscription.readEnabled;
        retentionByNode[subscription.forumHostId]![subscription.localBoardId] =
            subscription.retentionDays;
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
      _showInitialForumHostDialogIfNeeded();
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

  void _showInitialForumHostDialogIfNeeded() {
    final initialUrl = widget.initialForumHostUrl?.trim();
    if (_shownInitialForumHostDialog ||
        initialUrl == null ||
        initialUrl.isEmpty) {
      return;
    }
    _shownInitialForumHostDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showAddRemoteNodeDialog(initialUrl: initialUrl));
    });
  }

  Future<void> _showAddRemoteNodeDialog({String? initialUrl}) async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => RemoteNodeFormDialog(initialUrl: initialUrl),
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

    // Compliance-review gap #2: capture the host's self-declared compliance
    // level at add time (best-effort) so saved hosts carry it. Display and
    // ranking input only — never trust-bearing.
    final compliance = await _fetchHostCompliance(data['url']!);
    if (hostComplianceNeedsWarning(compliance)) {
      if (!mounted) return;
      final addAnyway = await _confirmUndeclaredComplianceHost(compliance);
      if (addAnyway != true) return;
    }

    final node = RemoteNode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: data['name']!,
      url: data['url']!,
      accessToken: accessToken,
      createdAt: now,
      updatedAt: now,
      isActive: true,
      constitutionCompliance: compliance,
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

  Future<String?> _fetchHostCompliance(String url) async {
    final fetcher = widget.complianceFetcher;
    if (fetcher != null) return fetcher(url);
    final discoveryClient = RelayDiscoveryClient(baseUrl: url);
    try {
      return await discoveryClient.fetchHostConstitutionCompliance();
    } finally {
      discoveryClient.close();
    }
  }

  /// Confirm dialog before saving a host whose constitution compliance is
  /// unknown/undeclared or non-compliant. The constitution requires the
  /// compliance level to be visible when it affects user trust, but keeps it
  /// display-only — so the user may still add the host after seeing it.
  Future<bool?> _confirmUndeclaredComplianceHost(String? compliance) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('host_compliance_warning_dialog'),
        title: Text(
          dialogContext.uiCopy(
            zh: '主機憲章聲明',
            en: 'Host constitution compliance',
          ),
        ),
        content: Text(
          compliance == 'non_compliant'
              ? dialogContext.uiCopy(
                  zh:
                      '此主機聲明不符合憲章。加入後仍可同步與瀏覽，但它可能不遵守本應用的內容與身分保護規則。'
                      '此標示僅供顯示與排序參考。',
                  en:
                      'This host declares itself non-compliant with the '
                      'constitution. You can still add and browse it, but it '
                      'may not follow this app\'s content and identity '
                      'protections. The label is informational only.',
                )
              : dialogContext.uiCopy(
                  zh:
                      '此主機未聲明符合憲章。加入後仍可同步與瀏覽，但其行為未經評估。'
                      '此標示僅供顯示與排序參考。',
                  en:
                      'This host has not declared constitution compliance. '
                      'You can still add and browse it, but its behavior has '
                      'not been evaluated. The label is informational only.',
                ),
        ),
        actions: [
          TextButton(
            key: const Key('host_compliance_cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            key: const Key('host_compliance_add_anyway'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.uiCopy(zh: '仍要加入', en: 'Add anyway')),
          ),
        ],
      ),
    );
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
    final subscriptions = await _hostedBoardRepo.listSubscriptions(
      forumHostId: nodeId,
    );
    for (final subscription in subscriptions.where(
      (item) => item.localBoardId == boardId,
    )) {
      await _hostedBoardRepo.upsertSubscription(
        subscription.copyWith(readEnabled: enabled, updatedAt: DateTime.now()),
      );
    }
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
    final subscriptions = await _hostedBoardRepo.listSubscriptions(
      forumHostId: nodeId,
    );
    for (final subscription in subscriptions.where(
      (item) => item.localBoardId == boardId,
    )) {
      await _hostedBoardRepo.upsertSubscription(
        subscription.copyWith(
          retentionDays: retentionDays,
          updatedAt: DateTime.now(),
        ),
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
        remoteTombstoneRepository: DriftRemoteTombstoneRepository(widget.db),
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
        final text = SubpageL10n.of(context);
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                text.f('syncNodePullSummary', {
                  'name': node.name,
                  'count': result.activitiesProcessed,
                  'publish': _publishSummaryMessage(publishSummary),
                }),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                text.f('syncNodeFailed', {
                  'name': node.name,
                  'error': result.errorMessage ?? '',
                }),
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
            content: Text(
              SubpageL10n.of(
                context,
              ).f('syncNodeError', {'name': node.name, 'error': '$e'}),
            ),
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
        .where((item) => isPublishableContentForDid(item, widget.localDid))
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
    final text = SubpageL10n.of(context);
    var message = text.f('syncAllComplete', {
      'count': pulledActivities,
      'publish': _publishSummaryMessage(publishSummary),
    });
    if (pullErrors.isNotEmpty) {
      message += text.f('syncAllPullErrors', {'errors': pullErrors.join('; ')});
    }
    return message;
  }

  String _publishSummaryMessage(PublicPublishSummary summary) {
    final text = SubpageL10n.of(context);
    if (summary.errorMessage != null) {
      return text.f('publishFailed', {'error': summary.errorMessage!});
    }
    if (summary.publicItems == 0) {
      return text.t('publishNoPublic');
    }
    if (summary.enqueued == 0 &&
        summary.published == 0 &&
        summary.failed == 0) {
      final reasons = summary.skippedReasons.isEmpty
          ? text.t('publishNoNewTargetsReason')
          : summary.skippedReasons.join(', ');
      return text.f('publishNoNewTargets', {'reasons': reasons});
    }
    if (summary.failed > 0 && summary.failureReasons.isNotEmpty) {
      return text.f('publishResultReason', {
        'published': summary.published,
        'enqueued': summary.enqueued,
        'failed': summary.failed,
        'reason': summary.failureReasons.first,
      });
    }
    return text.f('publishResult', {
      'published': summary.published,
      'enqueued': summary.enqueued,
      'failed': summary.failed,
    });
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
                if (_localOnlyBoards.isNotEmpty) ...[
                  AnsibleMonoLabel(
                    context.uiCopy(zh: '僅本機 · LOCAL ONLY', en: 'LOCAL ONLY'),
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                  ),
                  AnsibleRuleGroup(
                    children: [
                      for (final board in _localOnlyBoards)
                        ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              board.title.trim().isEmpty
                                  ? '·'
                                  : board.title.trim().characters.first,
                            ),
                          ),
                          title: Text(board.title),
                          subtitle: Text(
                            context.uiCopy(
                              zh: '只保存在這台裝置，未與 Relay 同步',
                              en: 'Stored only on this device; not synced with a Relay',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
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
    final nodeBoards = _boardsForNode(node.id);
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
                        if (node.constitutionCompliance != null) ...[
                          const SizedBox(height: 4),
                          // Host-declared constitution compliance (gap #2):
                          // display-only, never trust-bearing.
                          Text(
                            'CONSTITUTION · '
                            '${node.constitutionCompliance!.toUpperCase()}',
                            style: const TextStyle(
                              fontFamily: AnsibleDesign.mono,
                              fontSize: 9,
                              letterSpacing: 1.2,
                              color: AnsibleDesign.inkFaint,
                            ),
                          ),
                        ],
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
                          for (final board in nodeBoards) {
                            await _toggleBoardSync(node.id, board.id, true);
                          }
                        },
                        child: Text(text.t('selectAll')),
                      ),
                      TextButton(
                        onPressed: () async {
                          // Clear all
                          for (final board in nodeBoards) {
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
                  if (nodeBoards.isEmpty)
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
                      children: nodeBoards.map((board) {
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
                                child: SwitchListTile(
                                  key: ValueKey(
                                    'board_sync_switch_${node.id}_${board.id}',
                                  ),
                                  value: isEnabled,
                                  onChanged: (enabled) {
                                    _toggleBoardSync(
                                      node.id,
                                      board.id,
                                      enabled,
                                    );
                                  },
                                  title: Text(board.title),
                                  subtitle: Text(
                                    isEnabled
                                        ? context.uiCopy(
                                            zh: '同步中 · 關閉後仍保留本機資料',
                                            en: 'Syncing · Turn off to keep a local-only copy',
                                          )
                                        : context.uiCopy(
                                            zh: '已暫停同步 · 本機資料已保留',
                                            en: 'Sync paused · Local data is preserved',
                                          ),
                                  ),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
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

  List<Board> _boardsForNode(String nodeId) {
    final boardIds = _boardSyncStatusByNode[nodeId]?.keys.toSet() ?? const {};
    return _boards.where((board) => boardIds.contains(board.id)).toList();
  }

  List<Board> get _localOnlyBoards {
    final remoteBoardIds = <String>{
      for (final statuses in _boardSyncStatusByNode.values) ...statuses.keys,
    };
    return _boards
        .where((board) => !remoteBoardIds.contains(board.id))
        .toList();
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
