import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:ansible_store/ansible_store.dart';

abstract class NostrRelayClient {
  Future<void> publish({required String endpoint, required NostrEvent event});
}

class NostrRelayFilter {
  final List<String> ids;
  final List<String> authors;
  final List<int> kinds;
  final int? since;
  final int? until;
  final int? limit;

  const NostrRelayFilter({
    this.ids = const [],
    this.authors = const [],
    this.kinds = const [],
    this.since,
    this.until,
    this.limit,
  });

  Map<String, dynamic> toJson() {
    return {
      if (ids.isNotEmpty) 'ids': ids,
      if (authors.isNotEmpty) 'authors': authors,
      if (kinds.isNotEmpty) 'kinds': kinds,
      if (since != null) 'since': since,
      if (until != null) 'until': until,
      if (limit != null) 'limit': limit,
    };
  }
}

abstract class NostrRelaySocket {
  Stream<dynamic> get stream;
  void add(String data);
  Future<void> close();
}

typedef NostrRelaySocketConnect = Future<NostrRelaySocket> Function(Uri uri);

class NostrWebSocketRelayClient implements NostrRelayClient {
  final NostrRelaySocketConnect connect;
  final Duration timeout;

  NostrWebSocketRelayClient({
    NostrRelaySocketConnect? connect,
    this.timeout = const Duration(seconds: 10),
  }) : connect = connect ?? _connectWebSocket;

  @override
  Future<void> publish({
    required String endpoint,
    required NostrEvent event,
  }) async {
    final socket = await connect(Uri.parse(endpoint));
    try {
      final ok = socket.stream
          .map(_decodeRelayMessage)
          .where((message) => _isTerminalForEvent(message, event.id))
          .first
          .timeout(timeout);
      socket.add(jsonEncode(['EVENT', event.toJson()]));
      final message = await ok;
      _validateOkMessage(message, event.id);
    } finally {
      await socket.close();
    }
  }

  Future<List<NostrEvent>> read({
    required String endpoint,
    required List<NostrRelayFilter> filters,
    String? subscriptionId,
  }) async {
    final subId =
        subscriptionId ?? 'ansible-${DateTime.now().microsecondsSinceEpoch}';
    final socket = await connect(Uri.parse(endpoint));
    final events = <NostrEvent>[];
    try {
      socket.add(jsonEncode(['REQ', subId, ...filters.map((f) => f.toJson())]));
      await for (final message
          in socket.stream.map(_decodeRelayMessage).timeout(timeout)) {
        if (!_isReadMessageForSubscription(message, subId)) continue;
        if (message.first == 'EOSE') break;
        events.add(
          NostrEvent.fromJson(
            Map<String, dynamic>.from(message[2] as Map<dynamic, dynamic>),
          ),
        );
      }
      socket.add(jsonEncode(['CLOSE', subId]));
      return events;
    } finally {
      await socket.close();
    }
  }

  static Future<NostrRelaySocket> _connectWebSocket(Uri uri) async {
    final socket = await WebSocket.connect(uri.toString());
    return _DartIoNostrRelaySocket(socket);
  }

  static List<dynamic> _decodeRelayMessage(dynamic message) {
    if (message is! String) {
      throw const NostrRelayPublishException('Relay sent non-text message');
    }
    final decoded = jsonDecode(message);
    if (decoded is! List<dynamic> || decoded.isEmpty) {
      throw const NostrRelayPublishException('Relay sent invalid message');
    }
    return decoded;
  }

  static bool _isTerminalForEvent(List<dynamic> message, String eventId) {
    final type = message.first;
    if (type == 'NOTICE') return true;
    return type == 'OK' && message.length >= 2 && message[1] == eventId;
  }

  static bool _isReadMessageForSubscription(
    List<dynamic> message,
    String subscriptionId,
  ) {
    if (message.first == 'NOTICE') {
      throw NostrRelayPublishException(
        message.length > 1 ? message[1].toString() : 'relay notice',
      );
    }
    if (message.length < 2 || message[1] != subscriptionId) return false;
    if (message.first == 'EOSE') return true;
    return message.first == 'EVENT' && message.length >= 3;
  }

  static void _validateOkMessage(List<dynamic> message, String eventId) {
    if (message.first == 'NOTICE') {
      final detail = message.length > 1 ? message[1] : 'relay notice';
      throw NostrRelayPublishException(detail.toString());
    }
    if (message.length < 4 || message[0] != 'OK' || message[1] != eventId) {
      throw const NostrRelayPublishException('Relay did not acknowledge event');
    }
    if (message[2] != true) {
      throw NostrRelayPublishException(message[3].toString());
    }
  }
}

class _DartIoNostrRelaySocket implements NostrRelaySocket {
  final WebSocket _socket;

  _DartIoNostrRelaySocket(this._socket);

  @override
  Stream<dynamic> get stream => _socket;

  @override
  void add(String data) {
    _socket.add(data);
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }
}

class NostrRelayPublishException implements Exception {
  final String message;

  const NostrRelayPublishException(this.message);

  @override
  String toString() => 'NostrRelayPublishException: $message';
}

class NostrPublicationResult {
  final int published;
  final int failed;

  const NostrPublicationResult({required this.published, required this.failed});
}

class NostrPublicationService {
  final ContentItemRepository contentItems;
  final PublicationRepository publications;
  final NostrKeyStore keyStore;
  final NostrEventSigner signer;
  final NostrRelayClient relayClient;

  NostrPublicationService({
    required this.contentItems,
    required this.publications,
    required this.keyStore,
    required this.signer,
    NostrRelayClient? relayClient,
  }) : relayClient = relayClient ?? NostrWebSocketRelayClient();

  Future<NostrPublicationResult> publishPending({int limit = 25}) async {
    final targets = await publications.listPendingTargets(
      protocol: PublicationProtocol.nostr,
      limit: limit,
    );
    var published = 0;
    var failed = 0;

    for (final target in targets) {
      final succeeded = await _publishTarget(target);
      if (succeeded) {
        published += 1;
      } else {
        failed += 1;
      }
    }

    return NostrPublicationResult(published: published, failed: failed);
  }

  Future<NostrPublicationResult> retryTarget(String targetId) async {
    await publications.resetTargetForRetry(targetId);
    final target = await publications.getTargetById(targetId);
    if (target == null || target.status != PublicationStatus.pending) {
      return const NostrPublicationResult(published: 0, failed: 0);
    }
    final succeeded = await _publishTarget(target);
    return NostrPublicationResult(
      published: succeeded ? 1 : 0,
      failed: succeeded ? 0 : 1,
    );
  }

  Future<bool> _publishTarget(PublicationTarget target) async {
    try {
      final intent = await publications.getIntentById(target.intentId);
      if (intent == null) {
        throw StateError('Publication intent ${target.intentId} not found.');
      }
      final content = await contentItems.getById(intent.contentItemId);
      if (content == null) {
        throw StateError('Content item ${intent.contentItemId} not found.');
      }
      final key = await keyStore.read();
      if (key == null) {
        throw StateError('No local Nostr key material found.');
      }

      final draft = _project(intent, content, key.publicKeyHex);
      final event = await signer.sign(draft);
      await relayClient.publish(endpoint: target.endpoint, event: event);
      await publications.markTargetPublished(
        target.targetId,
        remoteId: event.id,
      );
      await _completeIntentIfSettled(intent.intentId);
      return true;
    } catch (error) {
      await publications.markTargetFailed(target.targetId, error.toString());
      return false;
    }
  }

  NostrEventDraft _project(
    PublicationIntent intent,
    ContentItem content,
    String pubkey,
  ) {
    return switch (intent.action) {
      PublicationAction.publish || PublicationAction.update =>
        NostrContentProjection.projectContent(content, pubkey: pubkey),
      PublicationAction.delete => throw const NostrProjectionException(
        'Delete publication requires a prior Nostr event id.',
      ),
    };
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
}
