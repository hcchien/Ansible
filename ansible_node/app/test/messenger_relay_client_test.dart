import 'dart:convert';

import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('constructor accepts implementation-plan httpClient alias', () async {
    final requests = <http.Request>[];
    final client = MessengerRelayClient(
      relayBaseUrl: Uri.parse('http://localhost:4001'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'subject_did': 'did:plc:bob', 'devices': []}),
          200,
        );
      }),
    );

    final bundle = await client.fetchPreKeyBundle('did:plc:bob');

    expect(bundle.devices, isEmpty);
    expect(
      requests.single.url.path,
      '/api/v1/messenger/pre-key-bundles/did%3Aplc%3Abob',
    );
  });

  test('publishes device and sends ciphertext through relay APIs', () async {
    final requests = <http.Request>[];
    final client = MessengerRelayClient(
      relayBaseUrl: Uri.parse('http://localhost:4001'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'accepted': true}), 201);
      }),
    );

    await client.publishDevice(
      subjectDid: 'did:plc:alice',
      deviceId: 'msgdev_alice',
      bundle: {'messenger_identity_key': 'alice_identity'},
      binding: {'subject_did': 'did:plc:alice'},
      bindingSignature: 'dev-signature',
    );

    await client.sendMessage(
      messageId: 'msg_test',
      senderDid: 'did:plc:alice',
      senderDeviceId: 'msgdev_alice',
      recipientDid: 'did:plc:bob',
      recipientDeviceId: 'msgdev_bob',
      ciphertextType: 'pre_key_signal_message',
      ciphertext: 'base64-ciphertext',
      protocolVersion: 'signal-mvp-v1',
      createdAt: DateTime.utc(2026, 5, 14),
      requestSignature: 'dev-signature',
    );

    expect(requests[0].url.path, '/api/v1/messenger/devices');
    expect(requests[1].url.path, '/api/v1/messenger/messages');

    final publishBody = jsonDecode(requests[0].body) as Map<String, dynamic>;
    expect(publishBody['subject_did'], 'did:plc:alice');
    expect(publishBody['device_id'], 'msgdev_alice');
    expect(publishBody['bundle']['messenger_identity_key'], 'alice_identity');
    expect(publishBody['binding_signature'], 'dev-signature');

    final messageBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(messageBody['message_id'], 'msg_test');
    expect(messageBody['ciphertext'], 'base64-ciphertext');
    expect(messageBody['created_at'], '2026-05-14T00:00:00.000Z');
    expect(messageBody.containsKey('plaintext'), isFalse);
  });

  test('publishes pre-keys and reads reserved pre-key bundles', () async {
    final requests = <http.Request>[];
    final client = MessengerRelayClient(
      relayBaseUrl: Uri.parse('http://localhost:4001/root'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'accepted': true}), 201);
        }
        return http.Response(
          jsonEncode({
            'subject_did': 'did:plc:bob',
            'devices': [
              {
                'device_id': 'msgdev_bob',
                'messenger_identity_key': 'bob_identity',
                'signed_pre_key_id': 42,
                'signed_pre_key': 'bob_signed_pre_key',
                'signed_pre_key_signature': 'bob_signature',
                'one_time_pre_key_id': 1001,
                'one_time_pre_key': 'bob_one_time_pre_key',
                'binding': {'subject_did': 'did:plc:bob'},
                'binding_signature': 'binding-signature',
              },
            ],
          }),
          200,
        );
      }),
    );

    await client.publishPreKeys(
      subjectDid: 'did:plc:bob',
      deviceId: 'msgdev_bob',
      preKeys: const [
        {'pre_key_id': 1001, 'pre_key': 'bob_one_time_pre_key'},
      ],
      requestSignature: 'dev-signature',
    );
    final bundle = await client.fetchPreKeyBundle('did:plc:bob');

    expect(
      requests[0].url.toString(),
      'http://localhost:4001/root/api/v1/messenger/pre-keys',
    );
    expect(
      requests[1].url.toString(),
      'http://localhost:4001/root/api/v1/messenger/pre-key-bundles/did%3Aplc%3Abob',
    );
    expect(bundle.subjectDid, 'did:plc:bob');
    expect(bundle.devices.single.oneTimePreKeyId, 1001);
    expect(bundle.devices.single.oneTimePreKey, 'bob_one_time_pre_key');
  });

  test(
    'reads device availability without reserved one-time pre-key fields',
    () async {
      final requests = <http.Request>[];
      final client = MessengerRelayClient(
        relayBaseUrl: Uri.parse('http://localhost:4001'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'subject_did': 'did:plc:bob',
              'devices': [
                {
                  'device_id': 'msgdev_bob',
                  'messenger_identity_key': 'bob_identity',
                  'signed_pre_key_id': 42,
                  'signed_pre_key': 'bob_signed_pre_key',
                  'signed_pre_key_signature': 'bob_signature',
                  'has_one_time_pre_keys': true,
                },
              ],
            }),
            200,
          );
        }),
      );

      final availability = await client.fetchDeviceAvailability('did:plc:bob');

      expect(
        requests.single.url.path,
        '/api/v1/messenger/devices/did%3Aplc%3Abob',
      );
      expect(availability.subjectDid, 'did:plc:bob');
      expect(availability.devices.single.hasOneTimePreKeys, true);
      expect(availability.devices.single.deviceId, 'msgdev_bob');
    },
  );

  test('pulls mailbox and acks received messages', () async {
    final requests = <http.Request>[];
    final client = MessengerRelayClient(
      relayBaseUrl: Uri.parse('http://localhost:4001'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'messages': [
                {
                  'message_id': 'msg_test',
                  'sender_did': 'did:plc:alice',
                  'sender_device_id': 'msgdev_alice',
                  'recipient_did': 'did:plc:bob',
                  'recipient_device_id': 'msgdev_bob',
                  'ciphertext_type': 'pre_key_signal_message',
                  'ciphertext': 'base64-ciphertext',
                  'protocol_version': 'signal-mvp-v1',
                  'created_at': '2026-05-14T00:00:00.000Z',
                },
              ],
              'next_cursor': 'cursor-2',
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'accepted': true}), 200);
      }),
    );

    final mailbox = await client.pullMailbox(
      recipientDeviceId: 'msgdev_bob',
      cursor: 'cursor-1',
    );
    await client.ackMessage(
      messageId: 'msg_test',
      recipientDid: 'did:plc:bob',
      recipientDeviceId: 'msgdev_bob',
      requestSignature: 'dev-signature',
    );

    expect(requests[0].url.path, '/api/v1/messenger/messages');
    expect(
      requests[0].url.queryParameters['recipient_device_id'],
      'msgdev_bob',
    );
    expect(requests[0].url.queryParameters['cursor'], 'cursor-1');
    expect(mailbox.nextCursor, 'cursor-2');
    expect(mailbox.messages.single.messageId, 'msg_test');
    expect(mailbox.messages.single.ciphertext, 'base64-ciphertext');

    expect(requests[1].method, 'POST');
    expect(requests[1].url.path, '/api/v1/messenger/messages/msg_test/ack');
    final ackBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(ackBody['recipient_did'], 'did:plc:bob');
    expect(ackBody['recipient_device_id'], 'msgdev_bob');
  });

  test('relay errors are exposed as typed messenger exceptions', () async {
    final client = MessengerRelayClient(
      relayBaseUrl: Uri.parse('http://localhost:4001'),
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'device_not_found', 'message': 'missing'}),
          404,
        );
      }),
    );

    await expectLater(
      client.fetchPreKeyBundle('did:plc:bob'),
      throwsA(
        isA<MessengerRelayException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.error, 'error', 'device_not_found'),
      ),
    );
  });
}
