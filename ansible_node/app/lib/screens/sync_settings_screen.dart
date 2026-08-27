import 'dart:async';

import 'package:ansible_did/ansible_did.dart';
import 'package:flutter/material.dart';
import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/relay_discovery_client.dart';
import '../services/app_sync_service.dart';
import '../services/board_access_presentation_service.dart';
import '../services/private_board_crypto_service.dart';
import '../services/private_board_key_client.dart';
import '../services/nostr_publication_service.dart';
import '../services/nostr_relay_settings_store.dart';
import '../services/nostr_secure_key_store.dart';
import '../services/notification_preferences_controller.dart';
import '../services/notification_projector.dart';
import '../widgets/remote_node_form_dialog.dart';
import '../services/remote_sync_service.dart';
import '../services/ops_dispatch_service.dart';
import '../services/relay_reputation_presentation_service.dart';
import '../services/relay_identity_bootstrap_service.dart';
import '../services/user_presence_verifier.dart';
import '../services/sync_capability_service.dart';
import '../services/sync_authorization_controller.dart';
import '../services/platform_capabilities.dart';
import '../services/public_profile_credential_preferences.dart';
import '../services/public_profile_credential_presentation_service.dart';
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
  final UserPresenceVerifier? userPresenceVerifier;
  final PlatformCapabilities? platformCapabilities;
  final SyncAuthorizationController? syncAuthorizationController;

  const SyncSettingsScreen({
    super.key,
    required this.db,
    required this.localDid,
    this.initialForumHostUrl,
    this.complianceFetcher,
    this.userPresenceVerifier,
    this.platformCapabilities,
    this.syncAuthorizationController,
  });

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen>
    with WidgetsBindingObserver {
  static const int _retainForeverValue = 0;
  PlatformCapabilities get _capabilities =>
      widget.platformCapabilities ?? PlatformCapabilities.current;
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
  late final DriftOpsQueueRepository _opsQueueRepo;
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
  final Map<String, String> _syncCapabilitiesByNode = {};
  final Map<String, SyncCapabilityService> _syncCapabilityServices = {};
  late final SyncAuthorizationController _syncAuthorizationController;
  String? _expandedNodeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncAuthorizationController =
        widget.syncAuthorizationController ??
        (widget.userPresenceVerifier == null
            ? SyncAuthorizationController.shared
            : SyncAuthorizationController());
    _remoteNodeRepo = DriftRemoteNodeRepository(widget.db);
    _boardSyncConfigRepo = DriftBoardSyncConfigRepository(widget.db);
    _hostedBoardRepo = DriftHostedBoardRepository(widget.db);
    _boardRepo = DriftBoardRepository(widget.db);
    _threadRepo = DriftThreadRepository(widget.db);
    _postRepo = DriftPostRepository(widget.db);
    _contentItemRepo = DriftContentItemRepository(widget.db);
    _publicationRepo = DriftPublicationRepository(widget.db);
    _opsQueueRepo = DriftOpsQueueRepository(widget.db);
    _nostrKeyStore = const SecureStorageNostrKeyStore();
    _nostrRelaySettingsStore = const SecureStorageNostrRelaySettingsStore();
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SyncSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localDid != widget.localDid) {
      unawaited(_syncAuthorizationController.invalidate());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // `inactive` may be emitted while Face ID is on screen; treating that as
      // backgrounding would invalidate the context that is being authorized.
      unawaited(_syncAuthorizationController.invalidate());
    }
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

  Future<SyncAuthenticationSession?> _beginSyncAuthentication(
    String reason,
  ) async {
    final verifier = widget.userPresenceVerifier;
    if (verifier != null) {
      return await verifier.verify(reason: reason)
          ? const PresenceOnlySyncAuthenticationSession()
          : null;
    }
    final hardware = await HardwareAuthenticationSession.begin(
      localizedReason: reason,
    );
    if (hardware != null) return HardwareSyncAuthenticationSession(hardware);
    return await LocalDeviceUserPresenceVerifier().verify(reason: reason)
        ? const PresenceOnlySyncAuthenticationSession()
        : null;
  }

  RemoteSyncService _remoteSyncService({
    DidSigner? signer,
    bool allowProtectedBoardReads = false,
    bool reuseHardwareAuthenticationContext = false,
  }) {
    BoardReadAuthorization? authorizeBoardRead;
    if (allowProtectedBoardReads && signer != null) {
      final boardAccess = BoardAccessPresentationService(
        walletRepository: DriftWalletRepository(widget.db),
        didSigner: signer,
      );
      final boardCapabilities = <String, BoardAccessCapability>{};
      final preparedPrivateBoards = <String>{};
      final privateCrypto = PrivateBoardCryptoService();
      authorizeBoardRead = (board, requestUri) async {
        var capability = boardCapabilities[board.hostedBoardId];
        if (capability == null ||
            capability.policyVersion != board.accessPolicyVersion ||
            !capability.expiresAt.isAfter(
              DateTime.now().toUtc().add(const Duration(seconds: 5)),
            )) {
          capability = await boardAccess.authorize(
            forumHost: requestUri.replace(
              path: '',
              query: null,
              fragment: null,
            ),
            boardId: board.hostedBoardId,
            action: 'read',
            reuseAuthenticationContext: reuseHardwareAuthenticationContext,
          );
          boardCapabilities[board.hostedBoardId] = capability;
        }
        final privateKey =
            '${board.hostedBoardId}:${board.encryptionEpoch}:${board.accessPolicyVersion}';
        if (board.contentVisibility == 'end_to_end_encrypted' &&
            !preparedPrivateBoards.contains(privateKey)) {
          final host = requestUri.replace(
            path: '',
            query: null,
            fragment: null,
          );
          final keyClient = PrivateBoardKeyClient(
            forumHost: host,
            boardId: board.hostedBoardId,
            access: boardAccess,
          );
          final publicKey = await privateCrypto.ensureDeviceKey(
            board.hostedBoardId,
          );
          await keyClient.registerDevice(
            capability: capability,
            publicKeyHex: publicKey.publicKeyHex,
            reuseAuthenticationContext: reuseHardwareAuthenticationContext,
          );
          final envelope = await keyClient.currentEnvelope(
            capability: capability,
            reuseAuthenticationContext: reuseHardwareAuthenticationContext,
          );
          if (envelope.epoch != board.encryptionEpoch ||
              envelope.policyVersion != board.accessPolicyVersion) {
            throw const PrivateBoardCryptoException('stale_epoch_envelope');
          }
          await privateCrypto.unwrapEpochKey(envelope);
          preparedPrivateBoards.add(privateKey);
        }
        return boardAccess.proofHeaders(
          capability: capability,
          method: 'GET',
          requestUri: requestUri,
          scope: 'read',
          reuseAuthenticationContext: reuseHardwareAuthenticationContext,
        );
      };
    }

    return RemoteSyncService(
      remoteNodeRepo: _remoteNodeRepo,
      boardSyncConfigRepo: _boardSyncConfigRepo,
      hostedBoardRepo: _hostedBoardRepo,
      boardRepo: _boardRepo,
      threadRepo: _threadRepo,
      postRepo: _postRepo,
      reactionRepository: DriftReactionRepository(widget.db),
      notificationProjector: NotificationProjector(
        notifications: DriftNotificationRepository(widget.db),
        localDid: widget.localDid,
        threadRepository: _threadRepo,
        postRepository: _postRepo,
        contactRepository: DriftContactRepository(widget.db),
        isCategoryEnabled: NotificationPreferencesController().categoryEnabled,
      ),
      remoteTombstoneRepository: DriftRemoteTombstoneRepository(widget.db),
      authorizeBoardRead: authorizeBoardRead,
    );
  }

  SyncResult _mergeSyncResults(SyncResult initial, SyncResult signed) {
    final processed = initial.activitiesProcessed + signed.activitiesProcessed;
    if (!initial.success || !signed.success) {
      return SyncResult.failure(
        errorMessage: [
          if (!initial.success) initial.errorMessage,
          if (!signed.success) signed.errorMessage,
        ].whereType<String>().join('; '),
        activitiesProcessed: processed,
        newCursor: signed.newCursor != 0 ? signed.newCursor : initial.newCursor,
      );
    }
    return SyncResult.success(
      activitiesProcessed: processed,
      newCursor: signed.newCursor != 0 ? signed.newCursor : initial.newCursor,
    );
  }

  Future<SyncResult> _performSync(
    RemoteNode node, {
    bool showSnackBar = true,
    bool requireUserPresence = true,
  }) async {
    if (_syncingNodes.values.any((value) => value)) {
      return SyncResult.failure(errorMessage: 'sync_in_progress');
    }
    final authenticationReason = context.uiCopy(
      zh: '即將以你的身分簽署並上傳待同步資料，或存取受保護看板。請確認由你本人操作。',
      en: 'Elix needs to sign pending sync data or access a protected board. Confirm that this is you.',
    );
    setState(() {
      _syncingNodes[node.id] = true;
    });
    SyncAuthorizationGrant? authorizationGrant;

    try {
      final client = RelayApiClient(baseUrl: node.url);
      if (node.accessToken != null) {
        client.setAccessToken(node.accessToken);
      }
      // Public data is pulled before asking for user presence. Protected-board
      // cursors remain untouched until an authenticated pass.
      final initialResult = await _remoteSyncService().syncFromNode(
        client,
        node,
      );
      final planningService = _relayPushService(DidSignerImpl());
      final requirement = requireUserPresence
          ? await planningService.authorizationRequirement(
              remoteNodeId: node.id,
            )
          : const SyncAuthorizationRequirement();
      String? syncCapability;
      var result = initialResult;
      var opsSummary = const OpsDispatchSummary();

      if (requirement.isRequired) {
        authorizationGrant = await _syncAuthorizationController.acquire(
          scope: widget.localDid,
          authenticate: () => _beginSyncAuthentication(authenticationReason),
        );
        if (authorizationGrant == null) {
          await _loadData();
          if (mounted && showSnackBar) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.uiCopy(
                    zh: '已完成公開資料拉取；未完成裝置驗證，因此未處理需簽署的同步項目。',
                    en: 'Public data was pulled. Signed sync work was skipped because device authentication was not completed.',
                  ),
                ),
              ),
            );
          }
          return SyncResult.failure(
            errorMessage: 'device_auth_cancelled',
            activitiesProcessed: initialResult.activitiesProcessed,
            newCursor: initialResult.newCursor,
          );
        }

        final reuseHardwareAuthenticationContext =
            authorizationGrant.reuseHardwareAuthenticationContext;
        final syncDidSigner = DidSignerImpl(
          reuseAuthenticationContext: reuseHardwareAuthenticationContext,
        );
        if (requirement.relayWrites) {
          // Registration is a write prerequisite, not a read prerequisite.
          await _ensureRelayIdentity(node, syncDidSigner);
        }
        if (requirement.protectedBoardReads) {
          final protectedResult = await _remoteSyncService(
            signer: syncDidSigner,
            allowProtectedBoardReads: true,
            reuseHardwareAuthenticationContext:
                reuseHardwareAuthenticationContext,
          ).syncFromNode(client, node);
          result = _mergeSyncResults(initialResult, protectedResult);
        }

        if (requirement.relayWrites) {
          if (_capabilities.webAuthn) {
            final capability = await _syncCapabilityServices
                .putIfAbsent(
                  '${widget.localDid}\u0000${node.url}',
                  () => SyncCapabilityService(
                    baseUrl: node.url,
                    holderDid: widget.localDid,
                    platformCapabilities: _capabilities,
                    didSigner: syncDidSigner,
                  ),
                )
                .authorize();
            syncCapability = capability.token;
            _syncCapabilitiesByNode[node.id] = syncCapability;
            await RelayReputationPresentationService(
              walletRepository: DriftWalletRepository(widget.db),
              reputationRepository: DriftDidReputationRepository(widget.db),
              didSigner: syncDidSigner,
            ).present(holderDid: widget.localDid, node: node);
          }
          // One existing sync authorization and one signer are shared by the
          // whole batch. A Wallet switch never starts authentication, and
          // selected credentials must not trigger one Face ID prompt per VC.
          await PublicProfileCredentialPresentationService(
            walletRepository: DriftWalletRepository(widget.db),
            preferenceStore:
                const SecurePublicProfileCredentialPreferenceStore(),
            didSigner: syncDidSigner,
          ).presentSelected(holderDid: widget.localDid, node: node);
          opsSummary = await _relayPushService(
            syncDidSigner,
          ).pushLocalOpsTo(node, accessToken: syncCapability);
        }
      }

      // Reload to update last sync time
      await _loadData();

      if (mounted && showSnackBar) {
        final text = SubpageL10n.of(context);
        if (result.success &&
            opsSummary.rejected == 0 &&
            opsSummary.retryPending == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${text.f('syncNodePullSummary', {'name': node.name, 'count': result.activitiesProcessed})}${opsSummary.sent == 0 ? '' : context.uiCopy(zh: ' · Relay 已送出 ${opsSummary.sent} 項', en: ' · Relay sent ${opsSummary.sent} item(s)')}',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                text.f('syncNodeFailed', {
                  'name': node.name,
                  'error':
                      result.errorMessage ??
                      opsSummary.retryReason ??
                      'relay_ops_delivery_failed',
                }),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return result;
    } catch (e) {
      if (mounted && showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              SubpageL10n.of(context).f('syncNodeError', {
                'name': node.name,
                'error': userFacingError(context, e),
              }),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return SyncResult.failure(errorMessage: e.toString());
    } finally {
      await authorizationGrant?.release();
      if (mounted) {
        setState(() {
          _syncingNodes[node.id] = false;
        });
      }
    }
  }

  AppSyncService _relayPushService(DidSigner signer) => AppSyncService(
    remoteNodeRepo: _remoteNodeRepo,
    boardSyncConfigRepo: _boardSyncConfigRepo,
    hostedBoardRepo: _hostedBoardRepo,
    boardRepo: _boardRepo,
    threadRepo: _threadRepo,
    postRepo: _postRepo,
    reactionRepository: DriftReactionRepository(widget.db),
    contentItemRepo: _contentItemRepo,
    publicationRepo: _publicationRepo,
    relaySettings: _nostrRelaySettingsStore,
    keyStore: _nostrKeyStore,
    opsQueueRepo: _opsQueueRepo,
    opsDispatchService: OpsDispatchService(
      repository: _opsQueueRepo,
      signer: signer,
    ),
    didSigner: signer,
    followerDid: widget.localDid,
    contactRepository: DriftContactRepository(widget.db),
    walletRepository: DriftWalletRepository(widget.db),
    profileCredentialPreferences:
        const SecurePublicProfileCredentialPreferenceStore(),
    allowIdentityWrites: _capabilities.webAuthn,
  );

  /// A Relay-local handle is presentation and routing data, not the DID. If a
  /// new Relay space already owns the suggested name, keep the existing DID
  /// and let the user choose another name for that one Relay only.
  Future<void> _ensureRelayIdentity(RemoteNode node, DidSigner signer) async {
    String? preferredHandleSuffix;
    while (true) {
      try {
        await RelayIdentityBootstrapService.ensureVerified(
          did: widget.localDid,
          baseUrl: node.url,
          signer: signer,
          preferredHandleSuffix: preferredHandleSuffix,
        );
        return;
      } on RelayHandleConflict catch (conflict) {
        final selected = await _chooseRelayHandle(
          node: node,
          suggestedSuffix: conflict.suggestedSuffix,
        );
        if (selected == null) {
          throw StateError('relay_handle_selection_cancelled');
        }
        preferredHandleSuffix = selected;
      }
    }
  }

  Future<String?> _chooseRelayHandle({
    required RemoteNode node,
    required String suggestedSuffix,
  }) async {
    final controller = TextEditingController(text: suggestedSuffix);
    try {
      return await showDialog<String>(
        context: context,
        // A handle collision is recoverable and must never be interpreted as
        // a request to abandon sync just because the user tapped the modal
        // barrier while changing Relay spaces.
        barrierDismissible: false,
        builder: (dialogContext) {
          var invalid = false;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              title: Text(
                dialogContext.uiCopy(
                  zh: '設定此 Relay 的名稱',
                  en: 'Choose a name for this Relay',
                ),
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (invalid) setDialogState(() => invalid = false);
                },
                decoration: InputDecoration(
                  labelText: dialogContext.uiCopy(zh: '帳號名稱', en: 'Handle'),
                  helperText: dialogContext.uiCopy(
                    zh: '可輸入名稱或完整 handle（例如 name.elix.cool）。這個名稱只屬於「${node.name}」；你的 DID、內容與憑證不會改變。',
                    en: 'Enter a name or full handle (for example name.elix.cool). It belongs only to ${node.name}; your DID, content, and credentials do not change.',
                  ),
                  errorText: invalid
                      ? dialogContext.uiCopy(
                          zh: '請輸入 3–63 個英數或連字號，且開頭與結尾須為英數。',
                          en: 'Use 3–63 letters, digits, or hyphens; start and end with a letter or digit.',
                        )
                      : null,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    dialogContext.uiCopy(zh: '取消同步', en: 'Cancel sync'),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final selected = controller.text.trim().toLowerCase();
                    final suffix = selected.endsWith('.elix.cool')
                        ? selected.substring(
                            0,
                            selected.length - '.elix.cool'.length,
                          )
                        : selected;
                    if (suffix.length < 3 ||
                        !RegExp(
                          r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$',
                        ).hasMatch(suffix)) {
                      setDialogState(() => invalid = true);
                      return;
                    }
                    Navigator.of(dialogContext).pop(suffix);
                  },
                  child: Text(
                    dialogContext.uiCopy(zh: '使用此名稱', en: 'Use this name'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _syncAllNodes() async {
    var pulledActivities = 0;
    final pullErrors = <String>[];
    for (final node in _remoteNodes) {
      if (node.isActive) {
        final result = await _performSync(node, showSnackBar: false);
        pulledActivities += result.activitiesProcessed;
        if (!result.success) {
          pullErrors.add('${node.name}: ${result.errorMessage}');
          // One cancelled ceremony must not turn "sync all" into a series of
          // repeated Face ID prompts for the remaining nodes.
          if (result.errorMessage == 'device_auth_cancelled') break;
        }
      }
    }
    if (!mounted) return;
    final message = _syncAllSummaryMessage(
      pulledActivities: pulledActivities,
      pullErrors: pullErrors,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _syncAllSummaryMessage({
    required int pulledActivities,
    required List<String> pullErrors,
  }) {
    final text = SubpageL10n.of(context);
    var message = text.f('syncAllComplete', {'count': pulledActivities});
    if (pullErrors.isNotEmpty) {
      message += text.f('syncAllPullErrors', {'errors': pullErrors.join('; ')});
    }
    return message;
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
      title: context.uiCopy(zh: '同步', en: 'Sync'),
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
                if (!_capabilities.webAuthn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                    child: Container(
                      key: const Key('sync_read_only_platform_notice'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AnsibleDesign.ochre.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.uiCopy(
                          zh: '此平台沒有可用的 WebAuthn。Relay 讀取同步仍可使用，但上傳與公開發佈會保持停用，不會退回 cookie 或未簽章寫入。',
                          en: 'WebAuthn is unavailable on this platform. Relay pull sync remains available, while uploads and public publication stay disabled; Elix will not fall back to cookie-only or unsigned writes.',
                        ),
                      ),
                    ),
                  ),
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
    final anyNodeSyncing = _syncingNodes.values.any((value) => value);
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
                    onPressed: anyNodeSyncing ? null : () => _performSync(node),
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
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    switchTheme:
                                        AnsibleDesign.paperSwitchTheme(),
                                  ),
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
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 132,
                                child: DropdownButtonFormField<int>(
                                  initialValue: retentionValue,
                                  isExpanded: true,
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
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
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
