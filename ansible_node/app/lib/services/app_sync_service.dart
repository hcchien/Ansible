import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';

import 'content_publication_service.dart';
import 'host_moderation_sync_service.dart';
import 'issuer_attestation_service.dart';
import 'notification_projector.dart';
import 'nostr_publication_service.dart';
import 'nostr_relay_settings_store.dart';
import 'ops_dispatch_service.dart';
import 'relay_identity_client.dart';
import 'relay_ops_client.dart';
import 'remote_sync_service.dart';
import 'relay_reputation_presentation_service.dart';
import 'sync_capability_service.dart';

bool isPublishableContentForDid(ContentItem item, String localDid) {
  return item.authorDid == localDid &&
      item.visibility != ContentVisibility.private &&
      !item.localOnly;
}

class AppSyncResult {
  const AppSyncResult({
    required this.pulledActivities,
    required this.publishSummary,
    this.pullErrors = const [],
    this.reputationErrors = const [],
  });

  final int pulledActivities;
  final PublicPublishSummary publishSummary;
  final List<String> pullErrors;
  final List<String> reputationErrors;

  bool get success =>
      pullErrors.isEmpty &&
      reputationErrors.isEmpty &&
      publishSummary.errorMessage == null;
}

class PublicPublishSummary {
  const PublicPublishSummary({
    required this.publicItems,
    this.enqueued = 0,
    this.published = 0,
    this.failed = 0,
    this.skipped = 0,
    this.skippedReasons = const {},
    this.failureReasons = const {},
    this.errorMessage,
  });

  final int publicItems;
  final int enqueued;
  final int published;
  final int failed;
  final int skipped;
  final Set<String> skippedReasons;
  final Set<String> failureReasons;
  final String? errorMessage;
}

class RelayPullSummary {
  const RelayPullSummary({
    required this.pulledActivities,
    this.pullErrors = const [],
  });

  final int pulledActivities;
  final List<String> pullErrors;

  bool get success => pullErrors.isEmpty;
}

class AppSyncService {
  AppSyncService({
    required RemoteNodeRepository remoteNodeRepo,
    required BoardSyncConfigRepository boardSyncConfigRepo,
    HostedBoardRepository? hostedBoardRepo,
    required BoardRepository boardRepo,
    required ThreadRepository threadRepo,
    required PostRepository postRepo,
    required ContentItemRepository contentItemRepo,
    required PublicationRepository publicationRepo,
    required NostrRelaySettingsStore relaySettings,
    required NostrKeyStore keyStore,
    FollowRepository? followRepository,
    ContactRepository? contactRepository,
    DidReputationRepository? didReputationRepo,
    String? followerDid,
    NotificationProjector? notificationProjector,
    HostModerationSyncService? hostModerationSync,
    RemoteTombstoneRepository? remoteTombstoneRepository,
    OpsQueueRepository? opsQueueRepo,
    OpsDispatchService? opsDispatchService,
    NostrSigningBridge signingBridge = const SchnorrSigningBridge(),
    DidSigner? didSigner,
    NostrRelayClient? relayClient,
    RelayPublicationClient? relayPublicationClient,
    RelayIdentityClient? identityClient,
    RelayReputationPresentationService? reputationPresentationService,
    SyncCapabilityService Function(RemoteNode node)? syncCapabilityService,
    BoardReadAuthorization? authorizeBoardRead,
    BoardWriteAuthorization? authorizeBoardWrite,
  }) : _remoteNodeRepo = remoteNodeRepo,
       _followRepository = followRepository,
       _contactRepository = contactRepository,
       _didReputationRepo = didReputationRepo,
       _followerDid = followerDid,
       _notificationProjector = notificationProjector,
       _hostModerationSync = hostModerationSync,
       _remoteTombstoneRepository = remoteTombstoneRepository,
       _opsQueueRepo = opsQueueRepo,
       _opsDispatchService = opsDispatchService,
       _boardSyncConfigRepo = boardSyncConfigRepo,
       _hostedBoardRepo = hostedBoardRepo,
       _boardRepo = boardRepo,
       _threadRepo = threadRepo,
       _postRepo = postRepo,
       _contentItemRepo = contentItemRepo,
       _publicationRepo = publicationRepo,
       _relaySettings = relaySettings,
       _keyStore = keyStore,
       _signingBridge = signingBridge,
       _didSigner = didSigner,
       _relayClient = relayClient,
       _relayPublicationClient = relayPublicationClient,
       _identityClient = identityClient,
       _reputationPresentationService = reputationPresentationService,
       _syncCapabilityService = syncCapabilityService,
       _authorizeBoardRead = authorizeBoardRead,
       _authorizeBoardWrite = authorizeBoardWrite;

  final RemoteNodeRepository _remoteNodeRepo;
  final FollowRepository? _followRepository;
  final ContactRepository? _contactRepository;
  final DidReputationRepository? _didReputationRepo;
  final String? _followerDid;
  final NotificationProjector? _notificationProjector;
  final HostModerationSyncService? _hostModerationSync;
  final RemoteTombstoneRepository? _remoteTombstoneRepository;
  final OpsQueueRepository? _opsQueueRepo;
  final OpsDispatchService? _opsDispatchService;
  final BoardSyncConfigRepository _boardSyncConfigRepo;
  final HostedBoardRepository? _hostedBoardRepo;
  final BoardRepository _boardRepo;
  final ThreadRepository _threadRepo;
  final PostRepository _postRepo;
  final ContentItemRepository _contentItemRepo;
  final PublicationRepository _publicationRepo;
  final NostrRelaySettingsStore _relaySettings;
  final NostrKeyStore _keyStore;
  final NostrSigningBridge _signingBridge;
  final DidSigner? _didSigner;
  final NostrRelayClient? _relayClient;
  final RelayPublicationClient? _relayPublicationClient;
  final RelayIdentityClient? _identityClient;
  final RelayReputationPresentationService? _reputationPresentationService;
  final SyncCapabilityService Function(RemoteNode node)? _syncCapabilityService;
  final BoardReadAuthorization? _authorizeBoardRead;
  final BoardWriteAuthorization? _authorizeBoardWrite;

  // Portable issuer re-verification (federation trust): one service per
  // relay node, kept for the AppSyncService lifetime so its per-DID verified
  // cache survives across sync passes.
  final Map<String, IssuerAttestationService> _attestationServices = {};

  IssuerAttestationService _attestationServiceFor(String nodeUrl) {
    return _attestationServices.putIfAbsent(
      nodeUrl,
      () => IssuerAttestationService(relayBaseUrl: nodeUrl),
    );
  }

  Future<AppSyncResult> syncAll({
    bool pullRemote = true,
    bool pushLocal = true,
  }) async {
    final pullSummary = pullRemote
        ? await pullLatestFromRelays()
        : const RelayPullSummary(pulledActivities: 0);

    final reputationErrors = <String>[];
    final capabilities = <String, String>{};
    if (pushLocal) {
      final presenter = _reputationPresentationService;
      final holderDid = _followerDid;
      if (presenter != null && holderDid != null) {
        final nodes = await _remoteNodeRepo.list();
        for (final node in nodes.where((item) => item.isActive)) {
          try {
            final capabilityService = _syncCapabilityService;
            if (capabilityService != null) {
              capabilities[node.id] = (await capabilityService(
                node,
              ).authorize()).token;
            }
            await presenter.present(holderDid: holderDid, node: node);
          } on Object catch (error) {
            reputationErrors.add('${node.name}: $error');
          }
        }
      }
      await _enqueuePublicContentOps();
      await _enqueueFederatedFollowOps();
      await _enqueueProfileOp();
      final activeNode = await _remoteNodeRepo.getActive();
      final queue = _opsQueueRepo;
      if (activeNode != null && queue != null) {
        // A manual sync is an explicit retry boundary. Policy-blocked local
        // content remains on-device and is retried only here, after credentials
        // or the board policy may have changed.
        await queue.retryBlocked();
        await OpsDispatchService(
          repository: queue,
          signer: _didSigner,
          relayClient: RelayOpsClient(
            baseUrl: activeNode.url,
            accessToken: capabilities[activeNode.id],
            requestHeaders: _boardWriteHeaders,
          ),
        ).flushPending();
      }
    }
    final publishSummary = pushLocal
        ? await bestEffortPublicPublish(
            () => publishPublicContent(syncCapabilities: capabilities),
          )
        : const PublicPublishSummary(publicItems: 0);
    return AppSyncResult(
      pulledActivities: pullSummary.pulledActivities,
      pullErrors: pullSummary.pullErrors,
      reputationErrors: reputationErrors,
      publishSummary: publishSummary,
    );
  }

  Future<Map<String, String>> _boardWriteHeaders(
    OpsQueueEntry entry,
    Uri requestUri,
  ) async {
    final authorize = _authorizeBoardWrite;
    final hostedBoards = _hostedBoardRepo;
    if (authorize == null || hostedBoards == null) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64Decode(entry.payload)));
    } on Object {
      return const {};
    }
    if (decoded is! Map || decoded['boardId'] is! String) return const {};
    final rawBoardId = decoded['boardId'] as String;
    final projections = await hostedBoards.listProjections();
    HostedBoardProjection? projection;
    for (final candidate in projections) {
      if (rawBoardId == candidate.hostedBoardId ||
          rawBoardId.endsWith('_${candidate.hostedBoardId}')) {
        projection = candidate;
        break;
      }
    }
    if (projection == null) return const {};
    final post = projection.accessPolicy['post'];
    if (post is! Map ||
        post['requirement'] == 'public' ||
        post['requirement'] == 'posting_policy') {
      return const {};
    }
    return authorize(projection, requestUri);
  }

  /// Enqueues relay ops for the user's public/unlisted murmur and note content
  /// so it propagates through the op stream into followers' feeds. Idempotent:
  /// an entity that already has an op (any status) is skipped. Best-effort —
  /// failures never break the rest of the sync. Flushing the queue is the
  /// existing ops-dispatch responsibility.
  Future<int> _enqueuePublicContentOps() async {
    final dispatch = _opsDispatchService;
    final queue = _opsQueueRepo;
    if (dispatch == null || queue == null) return 0;

    try {
      final items = (await _contentItemRepo.list()).where((item) {
        final isFeedMode =
            item.mode == ContentMode.murmur || item.mode == ContentMode.note;
        return isFeedMode &&
            (_followerDid == null ||
                isPublishableContentForDid(item, _followerDid)) &&
            item.visibility != ContentVisibility.private &&
            !item.localOnly &&
            item.status == ContentStatus.active &&
            !item.isDeleted;
      }).toList();
      if (items.isEmpty) return 0;

      final existingEntityIds = {
        for (final op in await queue.listAll(limit: 1000)) op.entityId,
      };

      var enqueued = 0;
      for (final item in items) {
        if (existingEntityIds.contains(item.id)) continue;
        final entry = item.mode == ContentMode.note
            ? CrdtOpBuilder.createNote(
                authorDid: item.authorDid,
                entityId: item.id,
                body: item.body,
                title: item.title,
                visibility: item.visibility.name,
                publishedAt: item.publishedAt,
              )
            : CrdtOpBuilder.createMurmur(
                authorDid: item.authorDid,
                entityId: item.id,
                text: item.body,
                visibility: item.visibility.name,
                publishedAt: item.publishedAt,
              );
        await dispatch.signAndEnqueue(entry);
        await _contentItemRepo.update(item.copyWith(signatureVerified: true));
        enqueued += 1;
      }
      return enqueued;
    } catch (_) {
      // Best-effort: never let op enqueueing break sync.
      return 0;
    }
  }

  /// Enqueues relay ops announcing the user's **federated** follow edges so the
  /// AppView can build its follow graph and fan content out to this reader's home
  /// timeline. Only federated follows are published; `localOnly` follows never
  /// leave the device. Converges to the current edge set: a target whose latest
  /// published follow op no longer matches its desired state gets an
  /// insert/delete op. Best-effort — never breaks the rest of sync.
  Future<int> _enqueueFederatedFollowOps() async {
    final dispatch = _opsDispatchService;
    final queue = _opsQueueRepo;
    final follows = _followRepository;
    final followerDid = _followerDid;
    if (dispatch == null ||
        queue == null ||
        follows == null ||
        followerDid == null ||
        followerDid.isEmpty) {
      return 0;
    }

    try {
      final edges = await follows.listFollowing(
        followerDid,
        targetType: FollowTargetType.user,
      );

      // Desired federated follow targets (DIDs), accepted only.
      final desired = <String>{};
      for (final edge in edges.where(
        (e) =>
            e.status == FollowStatus.accepted &&
            e.visibility == FollowVisibility.federated,
      )) {
        final target = await follows.getTarget(edge.targetId);
        final did = target?.did ?? target?.canonicalUri;
        if (did != null && did.isNotEmpty) desired.add(did);
      }

      // Latest published follow-op type per target (entityId == targetDid).
      final latestOp = <String, OpsQueueEntry>{};
      for (final op in await queue.listAll(limit: 1000)) {
        if (op.entityType != 'follow') continue;
        final prev = latestOp[op.entityId];
        if (prev == null || op.createdAt.isAfter(prev.createdAt)) {
          latestOp[op.entityId] = op;
        }
      }

      var enqueued = 0;

      // Follow: desired targets whose latest op is not an active insert.
      for (final did in desired) {
        if (latestOp[did]?.opType == 'insert') continue;
        await dispatch.signAndEnqueue(
          CrdtOpBuilder.createFollow(followerDid: followerDid, targetDid: did),
        );
        enqueued += 1;
      }

      // Unfollow: previously-followed targets no longer desired.
      for (final entry in latestOp.entries) {
        if (entry.value.opType == 'insert' && !desired.contains(entry.key)) {
          await dispatch.signAndEnqueue(
            CrdtOpBuilder.deleteFollow(
              followerDid: followerDid,
              targetDid: entry.key,
            ),
          );
          enqueued += 1;
        }
      }

      return enqueued;
    } catch (_) {
      // Best-effort: never let follow-op enqueueing break sync.
      return 0;
    }
  }

  /// Publishes the user's own **public** profile (handle / display name / avatar)
  /// as a `profile` op so they are findable in the actor directory. Only the
  /// public subset of the self ContactRecord is published; re-publishes only when
  /// that subset changes. Best-effort.
  Future<int> _enqueueProfileOp() async {
    final dispatch = _opsDispatchService;
    final queue = _opsQueueRepo;
    final contacts = _contactRepository;
    final did = _followerDid;
    if (dispatch == null ||
        queue == null ||
        contacts == null ||
        did == null ||
        did.isEmpty) {
      return 0;
    }

    try {
      final self = await contacts.contactForDid(did);
      if (self == null) return 0;

      final handle = _blank(self.handle);
      final displayName = _blank(self.displayName);
      final avatarUrl = _blank(self.avatarUrl);
      // Nothing public to announce yet.
      if (handle == null && displayName == null) return 0;

      // Skip if the last published profile already matches the public subset.
      OpsQueueEntry? latest;
      for (final op in await queue.listAll(limit: 1000)) {
        if (op.entityType != 'profile') continue;
        if (latest == null || op.createdAt.isAfter(latest.createdAt)) {
          latest = op;
        }
      }
      if (latest != null) {
        final prev = CrdtOpBuilder.decodePayload(latest.payload);
        if (_blank(prev['handle'] as String?) == handle &&
            _blank(prev['displayName'] as String?) == displayName &&
            _blank(prev['avatarUrl'] as String?) == avatarUrl) {
          return 0;
        }
      }

      await dispatch.signAndEnqueue(
        CrdtOpBuilder.createProfile(
          authorDid: did,
          handle: handle,
          displayName: displayName,
          avatarUrl: avatarUrl,
        ),
      );
      return 1;
    } catch (_) {
      // Best-effort: never let profile publishing break sync.
      return 0;
    }
  }

  static String? _blank(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<RelayPullSummary> pullLatestFromRelays() async {
    final nodes = await _remoteNodeRepo.list();
    var pulledActivities = 0;
    final pullErrors = <String>[];
    for (final node in nodes.where((node) => node.isActive)) {
      final client = RelayApiClient(baseUrl: node.url);
      if (node.accessToken != null) {
        client.setAccessToken(node.accessToken);
      }
      final result = await RemoteSyncService(
        remoteNodeRepo: _remoteNodeRepo,
        boardSyncConfigRepo: _boardSyncConfigRepo,
        hostedBoardRepo: _hostedBoardRepo,
        boardRepo: _boardRepo,
        threadRepo: _threadRepo,
        postRepo: _postRepo,
        followRepository: _followRepository,
        contentItemRepo: _contentItemRepo,
        didReputationRepo: _didReputationRepo,
        followerDid: _followerDid,
        notificationProjector: _notificationProjector,
        remoteTombstoneRepository: _remoteTombstoneRepository,
        issuerAttestationService: _attestationServiceFor(node.url),
        identityClient: _identityClient,
        authorizeBoardRead: _authorizeBoardRead,
      ).syncFromNode(client, node, requireBoardSyncConfig: false);
      if (result.success) {
        pulledActivities += result.activitiesProcessed;
      } else {
        pullErrors.add('${node.name}: ${result.errorMessage}');
      }
      // After the node's op pull: refresh the host moderation overlay for
      // its subscribed hosted boards. Strictly best-effort — the service
      // swallows its own errors, and the extra guard here keeps any future
      // surprise from ever failing a sync pass.
      try {
        await _hostModerationSync?.syncForNode(node);
      } catch (_) {
        // Never let the moderation overlay break sync.
      }
    }
    return RelayPullSummary(
      pulledActivities: pulledActivities,
      pullErrors: pullErrors,
    );
  }

  Future<PublicPublishSummary> publishPublicContent({
    Map<String, String> syncCapabilities = const {},
  }) async {
    final publicItems = (await _contentItemRepo.list())
        .where(
          (item) => _followerDid == null
              ? item.visibility != ContentVisibility.private && !item.localOnly
              : isPublishableContentForDid(item, _followerDid),
        )
        .toList();
    if (publicItems.isEmpty) {
      return const PublicPublishSummary(publicItems: 0);
    }

    final distributionPreference = await _configuredDistributionPreference();
    if (distributionPreference == DistributionPreference.localOnly) {
      return PublicPublishSummary(
        publicItems: publicItems.length,
        skipped: publicItems.length,
        skippedReasons: const {'localOnly'},
      );
    }

    final activeNode = await _remoteNodeRepo.getActive();
    final publicationClient =
        _relayPublicationClient ??
        HttpRelayPublicationClient(
          accessToken: activeNode == null
              ? null
              : syncCapabilities[activeNode.id],
        );
    final service = ContentPublicationService(
      contentItems: _contentItemRepo,
      publications: _publicationRepo,
      relaySettings: _relaySettings,
      remoteNodes: _remoteNodeRepo,
      keyStore: _keyStore,
      signingBridge: _signingBridge,
      didSigner: _didSigner,
      relayClient: _relayClient,
      relayPublicationClient: publicationClient,
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
        skipped += 1;
        if (result.skippedReason != null) {
          skippedReasons.add(result.skippedReason!);
        }
      }
    }

    return PublicPublishSummary(
      publicItems: publicItems.length,
      enqueued: enqueued,
      published: published,
      failed: failed,
      skipped: skipped,
      skippedReasons: skippedReasons,
      failureReasons: failureReasons,
    );
  }

  Future<DistributionPreference> _configuredDistributionPreference() async {
    final nostrRelays = await _relaySettings.list();
    final remoteNodes = await _remoteNodeRepo.list();
    final hasNostr = nostrRelays.any((relay) => relay.write);
    final hasRelay = remoteNodes.any((node) => node.isActive);
    if (hasNostr && hasRelay) return DistributionPreference.nostrAndActivityPub;
    if (hasNostr) return DistributionPreference.nostr;
    if (hasRelay) return DistributionPreference.activityPub;
    return DistributionPreference.localOnly;
  }
}

Future<PublicPublishSummary> bestEffortPublicPublish(
  Future<PublicPublishSummary> Function() publish,
) async {
  try {
    return await publish();
  } catch (error) {
    return PublicPublishSummary(
      publicItems: 0,
      failed: 1,
      errorMessage: error.toString(),
    );
  }
}

String publicPublishSummaryMessage(PublicPublishSummary summary) {
  if (summary.errorMessage != null) {
    return 'public publish failed (${summary.errorMessage})';
  }
  if (summary.publicItems == 0) {
    return 'public publish 0 targets (no public notes/murmurs)';
  }
  if (summary.enqueued == 0 && summary.published == 0 && summary.failed == 0) {
    final reasons = summary.skippedReasons.isEmpty
        ? 'no new targets'
        : summary.skippedReasons.join(', ');
    return 'public publish 0 targets ($reasons)';
  }
  if (summary.failed > 0 && summary.failureReasons.isNotEmpty) {
    return 'public publish ${summary.published}/${summary.enqueued} targets, ${summary.failed} failed (${summary.failureReasons.first})';
  }
  return 'public publish ${summary.published}/${summary.enqueued} targets, ${summary.failed} failed';
}

String appSyncSummaryMessage(AppSyncResult result) {
  final parts = <String>[
    'pull ${result.pulledActivities} activities',
    publicPublishSummaryMessage(result.publishSummary),
  ];
  if (result.pullErrors.isNotEmpty) {
    parts.add('pull errors: ${result.pullErrors.join('; ')}');
  }
  if (result.reputationErrors.isNotEmpty) {
    parts.add('credential errors: ${result.reputationErrors.join('; ')}');
  }
  return 'sync complete: ${parts.join('; ')}';
}
