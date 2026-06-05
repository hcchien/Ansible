import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';

import 'content_publication_service.dart';
import 'nostr_publication_service.dart';
import 'nostr_relay_settings_store.dart';
import 'ops_dispatch_service.dart';
import 'relay_identity_client.dart';
import 'remote_sync_service.dart';

class AppSyncResult {
  const AppSyncResult({
    required this.pulledActivities,
    required this.publishSummary,
    this.pullErrors = const [],
  });

  final int pulledActivities;
  final PublicPublishSummary publishSummary;
  final List<String> pullErrors;

  bool get success => pullErrors.isEmpty && publishSummary.errorMessage == null;
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
    String? followerDid,
    OpsQueueRepository? opsQueueRepo,
    OpsDispatchService? opsDispatchService,
    NostrSigningBridge signingBridge = const SchnorrSigningBridge(),
    DidSigner? didSigner,
    NostrRelayClient? relayClient,
    RelayPublicationClient? relayPublicationClient,
    RelayIdentityClient? identityClient,
  }) : _remoteNodeRepo = remoteNodeRepo,
       _followRepository = followRepository,
       _followerDid = followerDid,
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
       _identityClient = identityClient;

  final RemoteNodeRepository _remoteNodeRepo;
  final FollowRepository? _followRepository;
  final String? _followerDid;
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

  Future<AppSyncResult> syncAll({bool pullRemote = true}) async {
    final pullSummary = pullRemote
        ? await pullLatestFromRelays()
        : const RelayPullSummary(pulledActivities: 0);

    await _enqueuePublicContentOps();
    final publishSummary = await bestEffortPublicPublish(publishPublicContent);
    return AppSyncResult(
      pulledActivities: pullSummary.pulledActivities,
      pullErrors: pullSummary.pullErrors,
      publishSummary: publishSummary,
    );
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
        enqueued += 1;
      }
      return enqueued;
    } catch (_) {
      // Best-effort: never let op enqueueing break sync.
      return 0;
    }
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
        followerDid: _followerDid,
        identityClient: _identityClient,
      ).syncFromNode(client, node, requireBoardSyncConfig: false);
      if (result.success) {
        pulledActivities += result.activitiesProcessed;
      } else {
        pullErrors.add('${node.name}: ${result.errorMessage}');
      }
    }
    return RelayPullSummary(
      pulledActivities: pulledActivities,
      pullErrors: pullErrors,
    );
  }

  Future<PublicPublishSummary> publishPublicContent() async {
    final publicItems = (await _contentItemRepo.list())
        .where(
          (item) =>
              item.visibility != ContentVisibility.private && !item.localOnly,
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

    final service = ContentPublicationService(
      contentItems: _contentItemRepo,
      publications: _publicationRepo,
      relaySettings: _relaySettings,
      remoteNodes: _remoteNodeRepo,
      keyStore: _keyStore,
      signingBridge: _signingBridge,
      didSigner: _didSigner,
      relayClient: _relayClient,
      relayPublicationClient: _relayPublicationClient,
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
  return 'sync complete: ${parts.join('; ')}';
}
