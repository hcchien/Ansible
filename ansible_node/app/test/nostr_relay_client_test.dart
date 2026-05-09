import 'dart:async';
import 'dart:convert';

import 'package:ansible_node/services/nostr_publication_service.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NostrWebSocketRelayClient', () {
    test('publishes EVENT and resolves on OK', () async {
      final socket = _FakeNostrRelaySocket();
      final client = NostrWebSocketRelayClient(connect: (_) async => socket);
      final event = _event(id: 'a' * 64);

      await client.publish(endpoint: 'wss://relay.example', event: event);

      final message = jsonDecode(socket.sent.single) as List<dynamic>;
      expect(message.first, 'EVENT');
      expect((message[1] as Map<String, dynamic>)['id'], event.id);
      expect(socket.closed, isTrue);
    });

    test('throws when relay rejects EVENT', () async {
      final socket = _FakeNostrRelaySocket(accept: false, message: 'blocked');
      final client = NostrWebSocketRelayClient(connect: (_) async => socket);

      await expectLater(
        client.publish(
          endpoint: 'wss://relay.example',
          event: _event(id: 'b' * 64),
        ),
        throwsA(isA<NostrRelayPublishException>()),
      );
      expect(socket.closed, isTrue);
    });

    test('reads events with REQ, stops on EOSE, and sends CLOSE', () async {
      final socket = _FakeNostrRelaySocket();
      final client = NostrWebSocketRelayClient(connect: (_) async => socket);
      final first = _event(id: 'e' * 64);
      final second = _event(id: 'f' * 64);
      socket.readEvents = [first, second];

      final events = await client.read(
        endpoint: 'wss://relay.example',
        filters: [
          const NostrRelayFilter(kinds: [1], limit: 2),
        ],
        subscriptionId: 'sub-test',
      );

      expect(events.map((event) => event.id), [first.id, second.id]);
      expect(jsonDecode(socket.sent.first), [
        'REQ',
        'sub-test',
        {
          'kinds': [1],
          'limit': 2,
        },
      ]);
      expect(jsonDecode(socket.sent.last), ['CLOSE', 'sub-test']);
      expect(socket.closed, isTrue);
    });
  });
}

NostrEvent _event({required String id}) {
  return NostrEvent(
    id: id,
    pubkey: 'c' * 64,
    createdAt: 1710000000,
    kind: 1,
    tags: const [],
    content: 'hello',
    sig: 'd' * 128,
  );
}

class _FakeNostrRelaySocket implements NostrRelaySocket {
  final bool accept;
  final String message;
  final List<String> sent = [];
  final StreamController<dynamic> _stream = StreamController<dynamic>();
  List<NostrEvent> readEvents = [];
  bool closed = false;

  _FakeNostrRelaySocket({this.accept = true, this.message = ''});

  @override
  Stream<dynamic> get stream => _stream.stream;

  @override
  void add(String data) {
    sent.add(data);
    final decoded = jsonDecode(data) as List<dynamic>;
    if (decoded.first == 'REQ') {
      final subscriptionId = decoded[1] as String;
      scheduleMicrotask(() {
        for (final event in readEvents) {
          _stream.add(jsonEncode(['EVENT', subscriptionId, event.toJson()]));
        }
        _stream.add(jsonEncode(['EOSE', subscriptionId]));
      });
      return;
    }
    if (decoded.first == 'CLOSE') return;
    final eventId = (decoded[1] as Map<String, dynamic>)['id'];
    scheduleMicrotask(() {
      _stream.add(jsonEncode(['OK', eventId, accept, message]));
    });
  }

  @override
  Future<void> close() async {
    closed = true;
    await _stream.close();
  }
}
