import 'dart:convert';
import 'dart:math';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'nostr_publication_service.dart';
import 'nostr_relay_settings_store.dart';

class ContentPublicationResult {
  const ContentPublicationResult({
    required this.enqueued,
    required this.published,
    required this.failed,
    this.errors = const [],
    this.skippedReason,
  });

  final int enqueued;
  final int published;
  final int failed;
  final List<String> errors;
  final String? skippedReason;
}

class RelayPublicationIntent {
  const RelayPublicationIntent({
    required this.intentId,
    required this.authorDid,
    required this.contentItemId,
    required this.action,
    required this.visibility,
    required this.payload,
    required this.payloadHash,
    required this.signature,
    required this.signatureScheme,
  });

  final String intentId;
  final String authorDid;
  final String contentItemId;
  final PublicationAction action;
  final ContentVisibility visibility;
  final Map<String, dynamic> payload;
  final String payloadHash;
  final String signature;
  final String signatureScheme;

  Map<String, dynamic> toJson() {
    return {
      'intent_id': intentId,
      'author_did': authorDid,
      'content_item_id': contentItemId,
      'action': action.name,
      'visibility': visibility.name,
      'payload': payload,
      'payload_hash': payloadHash,
      'signature': signature,
      'signature_scheme': signatureScheme,
    };
  }
}

class RelayPublicationResult {
  const RelayPublicationResult({required this.publicationId});

  final String publicationId;
}

abstract class RelayPublicationClient {
  Future<RelayPublicationResult> publish({
    required String baseUrl,
    required RelayPublicationIntent intent,
  });
}

class HttpRelayPublicationClient implements RelayPublicationClient {
  HttpRelayPublicationClient({
    http.Client? client,
    this.accessToken,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final String? accessToken;

  @override
  Future<RelayPublicationResult> publish({
    required String baseUrl,
    required RelayPublicationIntent intent,
  }) async {
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final response = await _client
        .post(
          baseUri.replace(path: '$basePath/api/v1/publication-intents'),
          headers: {
            'content-type': 'application/json',
            if (accessToken != null) 'authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(intent.toJson()),
        )
        .timeout(timeout);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 202 && response.statusCode != 409) {
      throw StateError(
        'Relay publication failed: ${response.statusCode} ${body['error']}',
      );
    }
    return RelayPublicationResult(
      publicationId: body['publication_id'] as String? ?? intent.intentId,
    );
  }
}

class ContentPublicationService {
  ContentPublicationService({
    required this.contentItems,
    required this.publications,
    required this.relaySettings,
    required this.keyStore,
    required this.signingBridge,
    this.remoteNodes,
    DidSigner? didSigner,
    NostrRelayClient? relayClient,
    RelayPublicationClient? relayPublicationClient,
  }) : didSigner = didSigner ?? DidSignerImpl(),
       relayClient = relayClient ?? NostrWebSocketRelayClient(),
       relayPublicationClient =
           relayPublicationClient ?? HttpRelayPublicationClient();

  final ContentItemRepository contentItems;
  final PublicationRepository publications;
  final NostrRelaySettingsStore relaySettings;
  final RemoteNodeRepository? remoteNodes;
  final NostrKeyStore keyStore;
  final NostrSigningBridge signingBridge;
  final DidSigner didSigner;
  final NostrRelayClient relayClient;
  final RelayPublicationClient relayPublicationClient;

  Future<ContentPublicationResult> publishContentItem(
    ContentItem item, {
    required DistributionPreference distributionPreference,
    PublicationAction action = PublicationAction.publish,
  }) async {
    if (item.visibility == ContentVisibility.private ||
        item.localOnly ||
        distributionPreference == DistributionPreference.localOnly) {
      return const ContentPublicationResult(
        enqueued: 0,
        published: 0,
        failed: 0,
        skippedReason: 'private_or_local_only',
      );
    }

    final shouldPublishNostr = _includesNostr(distributionPreference);
    final shouldPublishRelay = _includesActivityPub(distributionPreference);
    if (!shouldPublishNostr && !shouldPublishRelay) {
      return const ContentPublicationResult(
        enqueued: 0,
        published: 0,
        failed: 0,
        skippedReason: 'nostr_not_selected',
      );
    }

    final relays = shouldPublishNostr
        ? (await relaySettings.list()).where((relay) => relay.write).toList()
        : <NostrRelayPreference>[];
    final activeNode = shouldPublishRelay
        ? await remoteNodes?.getActive()
        : null;
    if (relays.isEmpty && activeNode == null) {
      final reason = shouldPublishRelay && !shouldPublishNostr
          ? 'no_active_relay'
          : 'no_write_relays';
      return ContentPublicationResult(
        enqueued: 0,
        published: 0,
        failed: 0,
        skippedReason: reason,
      );
    }

    final payload = _payload(item);
    final payloadHash = _payloadHash(payload);
    final now = DateTime.now().toUtc();
    final intentId = _stableId('intent', [
      item.id,
      action.name,
      item.updatedAt.toUtc().toIso8601String(),
    ]);
    final signature = shouldPublishRelay
        ? await _signRelayIntent(
            authorDid: item.authorDid,
            contentItemId: item.id,
            action: action,
            visibility: item.visibility,
            payloadHash: payloadHash,
          )
        : await _signNostrPolicy(payloadHash);
    final signatureScheme = shouldPublishRelay
        ? _identitySignatureScheme(signature)
        : 'schnorr-secp256k1';
    await contentItems.update(item.copyWith(signatureVerified: true));
    final existingTargets = await publications.listTargetsForIntent(intentId);
    final existingByEndpoint = {
      for (final target in existingTargets) target.endpoint: target,
    };
    final intent = PublicationIntent(
      intentId: intentId,
      authorDid: item.authorDid,
      contentItemId: item.id,
      action: action,
      visibility: item.visibility,
      distributionPreference: distributionPreference,
      status: PublicationStatus.pending,
      payloadHash: payloadHash,
      signature: signature,
      signatureScheme: signatureScheme,
      signedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final targets = [
      for (final relay in relays)
        if (!existingByEndpoint.containsKey(relay.url))
          PublicationTarget(
            targetId: _stableId('target', [intentId, relay.url]),
            intentId: intentId,
            protocol: PublicationProtocol.nostr,
            endpoint: relay.url,
            status: PublicationStatus.pending,
          ),
      if (activeNode != null && !existingByEndpoint.containsKey(activeNode.url))
        PublicationTarget(
          targetId: _stableId('target', [intentId, activeNode.url]),
          intentId: intentId,
          protocol: PublicationProtocol.activityPub,
          endpoint: activeNode.url,
          status: PublicationStatus.pending,
        ),
    ];
    final retryTargets = [
      for (final relay in relays)
        if (existingByEndpoint[relay.url]?.status == PublicationStatus.failed)
          existingByEndpoint[relay.url]!,
      if (activeNode != null &&
          existingByEndpoint[activeNode.url]?.status ==
              PublicationStatus.failed)
        existingByEndpoint[activeNode.url]!,
    ];

    if (targets.isNotEmpty ||
        await publications.getIntentById(intentId) == null) {
      await publications.enqueueIntent(intent, targets: targets);
    }
    for (final target in retryTargets) {
      await publications.resetTargetForRetry(target.targetId);
    }
    final publishTargets = [...targets, ...retryTargets];
    if (publishTargets.isEmpty) {
      return const ContentPublicationResult(
        enqueued: 0,
        published: 0,
        failed: 0,
      );
    }

    var published = 0;
    var failed = 0;
    final errors = <String>[];
    if (relays.isNotEmpty &&
        publishTargets.any(
          (target) => target.protocol == PublicationProtocol.nostr,
        )) {
      final publishResult = await NostrPublicationService(
        contentItems: contentItems,
        publications: publications,
        keyStore: keyStore,
        signer: ProductionNostrEventSigner(
          keyStore: keyStore,
          signingBridge: signingBridge,
        ),
        relayClient: relayClient,
      ).publishPending(limit: relays.length);
      published += publishResult.published;
      failed += publishResult.failed;
    }

    if (activeNode != null) {
      final relayTargets = publishTargets
          .where((target) => target.protocol == PublicationProtocol.activityPub)
          .toList();
      final target = relayTargets.isEmpty ? null : relayTargets.first;
      if (target != null) {
        try {
          final relayResult = await relayPublicationClient.publish(
            baseUrl: activeNode.url,
            intent: RelayPublicationIntent(
              intentId: intentId,
              authorDid: item.authorDid,
              contentItemId: item.id,
              action: action,
              visibility: item.visibility,
              payload: payload,
              payloadHash: payloadHash,
              signature: signature,
              signatureScheme: signatureScheme,
            ),
          );
          await publications.markTargetPublished(
            target.targetId,
            remoteId: relayResult.publicationId,
          );
          published += 1;
        } catch (error) {
          final errorMessage = error.toString();
          await publications.markTargetFailed(target.targetId, errorMessage);
          errors.add(errorMessage);
          failed += 1;
        }
      }
    }

    await _completeIntentIfSettled(intentId);
    return ContentPublicationResult(
      enqueued: publishTargets.length,
      published: published,
      failed: failed,
      errors: errors,
    );
  }

  Future<void> _completeIntentIfSettled(String intentId) async {
    final targets = await publications.listTargetsForIntent(intentId);
    if (targets.isEmpty) return;
    final hasPending = targets.any(
      (target) => target.status == PublicationStatus.pending,
    );
    if (!hasPending) {
      await publications.markIntentComplete(intentId);
    }
  }

  Future<String> _signRelayIntent({
    required String authorDid,
    required String contentItemId,
    required PublicationAction action,
    required ContentVisibility visibility,
    required String payloadHash,
  }) async {
    final message = jsonEncode([
      authorDid,
      contentItemId,
      action.name,
      visibility.name,
      payloadHash,
    ]);
    final signature = await didSigner.sign(utf8.encode(message));
    return signature.hex.toLowerCase();
  }

  Future<String> _signNostrPolicy(String payloadHash) async {
    final key = await _ensureKey();
    final signature = await signingBridge.signEventId(
      privateKeyHex: key.privateKeyHex,
      eventIdHex: payloadHash,
    );
    return signature.toLowerCase();
  }

  String _identitySignatureScheme(String signatureHex) {
    // Ed25519 is fixed-width (64 bytes). Hardware P-256 signatures are ASN.1
    // DER and therefore variable-width. The Relay negotiates the same scheme
    // names through the identity endpoint.
    return signatureHex.length == 128 ? 'ed25519' : 'p256-sha256';
  }

  Map<String, dynamic> _payload(ContentItem item) {
    return {
      'type': item.mode == ContentMode.note ? 'note' : 'murmur',
      if (item.title != null && item.title!.isNotEmpty) 'title': item.title,
      if (item.mode == ContentMode.murmur) 'text': item.body,
      'body': item.body,
      'created_at': item.createdAt.toUtc().toIso8601String(),
      'updated_at': item.updatedAt.toUtc().toIso8601String(),
    };
  }

  String _payloadHash(Map<String, dynamic> payload) {
    return sha256.convert(utf8.encode(_canonicalJson(payload))).toString();
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final entries =
          value.entries
              .map((entry) => MapEntry(entry.key.toString(), entry.value))
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      return '{${entries.map((entry) => '${jsonEncode(entry.key)}:${_canonicalJson(entry.value)}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }

  Future<NostrKeyMaterial> _ensureKey() async {
    final existing = await keyStore.read();
    if (existing != null) return existing;

    final random = Random.secure();
    while (true) {
      final privateKeyHex = List<int>.generate(
        32,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      try {
        final key = NostrKeyMaterial(
          privateKeyHex: privateKeyHex,
          publicKeyHex: SchnorrSigningBridge.derivePublicKeyHex(privateKeyHex),
        );
        await keyStore.save(key);
        return key;
      } on ArgumentError {
        // Extremely unlikely invalid scalar; retry with fresh secure entropy.
      }
    }
  }

  String _stableId(String prefix, List<String> parts) {
    final digest = sha256.convert(utf8.encode(parts.join('\u{1f}'))).toString();
    return '$prefix-$digest';
  }

  bool _includesNostr(DistributionPreference preference) {
    return preference == DistributionPreference.nostr ||
        preference == DistributionPreference.nostrAndActivityPub;
  }

  bool _includesActivityPub(DistributionPreference preference) {
    return preference == DistributionPreference.activityPub ||
        preference == DistributionPreference.nostrAndActivityPub;
  }
}
