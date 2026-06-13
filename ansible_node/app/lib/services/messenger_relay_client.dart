import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/protocol.dart';
import 'relay_identity_client.dart';

class MessengerPreKeyBundleResponse {
  final String subjectDid;
  final List<MessengerPreKeyBundleDevice> devices;

  const MessengerPreKeyBundleResponse({
    required this.subjectDid,
    required this.devices,
  });

  factory MessengerPreKeyBundleResponse.fromJson(Map<String, dynamic> json) {
    final devices = json['devices'];
    return MessengerPreKeyBundleResponse(
      subjectDid: json['subject_did'] as String,
      devices: devices is List
          ? devices
                .whereType<Map>()
                .map(
                  (device) => MessengerPreKeyBundleDevice.fromJson(
                    Map<String, dynamic>.from(device),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class MessengerPreKeyBundleDevice {
  final String deviceId;
  final String messengerIdentityKey;
  final int signedPreKeyId;
  final String signedPreKey;
  final String signedPreKeySignature;
  final int? oneTimePreKeyId;
  final String? oneTimePreKey;
  final Map<String, dynamic> binding;
  final String? bindingSignature;

  const MessengerPreKeyBundleDevice({
    required this.deviceId,
    required this.messengerIdentityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    this.oneTimePreKeyId,
    this.oneTimePreKey,
    this.binding = const {},
    this.bindingSignature,
  });

  factory MessengerPreKeyBundleDevice.fromJson(Map<String, dynamic> json) {
    final binding = json['binding'];
    return MessengerPreKeyBundleDevice(
      deviceId: json['device_id'] as String,
      messengerIdentityKey: json['messenger_identity_key'] as String,
      signedPreKeyId: json['signed_pre_key_id'] as int,
      signedPreKey: json['signed_pre_key'] as String,
      signedPreKeySignature: json['signed_pre_key_signature'] as String,
      oneTimePreKeyId: json['one_time_pre_key_id'] as int?,
      oneTimePreKey: json['one_time_pre_key'] as String?,
      binding: binding is Map ? Map<String, dynamic>.from(binding) : const {},
      bindingSignature: json['binding_signature'] as String?,
    );
  }
}

class MessengerDeviceAvailabilityResponse {
  final String subjectDid;
  final List<MessengerDeviceAvailability> devices;

  const MessengerDeviceAvailabilityResponse({
    required this.subjectDid,
    required this.devices,
  });

  factory MessengerDeviceAvailabilityResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final devices = json['devices'];
    return MessengerDeviceAvailabilityResponse(
      subjectDid: json['subject_did'] as String,
      devices: devices is List
          ? devices
                .whereType<Map>()
                .map(
                  (device) => MessengerDeviceAvailability.fromJson(
                    Map<String, dynamic>.from(device),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class MessengerDeviceAvailability {
  final String deviceId;
  final String messengerIdentityKey;
  final int signedPreKeyId;
  final String signedPreKey;
  final String signedPreKeySignature;
  final bool hasOneTimePreKeys;

  const MessengerDeviceAvailability({
    required this.deviceId,
    required this.messengerIdentityKey,
    required this.signedPreKeyId,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    required this.hasOneTimePreKeys,
  });

  factory MessengerDeviceAvailability.fromJson(Map<String, dynamic> json) {
    return MessengerDeviceAvailability(
      deviceId: json['device_id'] as String,
      messengerIdentityKey: json['messenger_identity_key'] as String,
      signedPreKeyId: json['signed_pre_key_id'] as int,
      signedPreKey: json['signed_pre_key'] as String,
      signedPreKeySignature: json['signed_pre_key_signature'] as String,
      hasOneTimePreKeys: json['has_one_time_pre_keys'] == true,
    );
  }
}

class MessengerMailboxResponse {
  final List<MessengerMailboxMessage> messages;
  final String? nextCursor;

  const MessengerMailboxResponse({required this.messages, this.nextCursor});

  factory MessengerMailboxResponse.fromJson(Map<String, dynamic> json) {
    final messages = json['messages'];
    return MessengerMailboxResponse(
      messages: messages is List
          ? messages
                .whereType<Map>()
                .map(
                  (message) => MessengerMailboxMessage.fromJson(
                    Map<String, dynamic>.from(message),
                  ),
                )
                .toList(growable: false)
          : const [],
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

class MessengerMailboxMessage {
  final String messageId;
  final String senderDid;
  final String senderDeviceId;
  final String recipientDid;
  final String recipientDeviceId;
  final String ciphertextType;
  final String ciphertext;
  final String protocolVersion;
  final DateTime? createdAt;

  const MessengerMailboxMessage({
    required this.messageId,
    required this.senderDid,
    required this.senderDeviceId,
    required this.recipientDid,
    required this.recipientDeviceId,
    required this.ciphertextType,
    required this.ciphertext,
    required this.protocolVersion,
    this.createdAt,
  });

  factory MessengerMailboxMessage.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'];
    return MessengerMailboxMessage(
      messageId: json['message_id'] as String,
      senderDid: json['sender_did'] as String,
      senderDeviceId: json['sender_device_id'] as String,
      recipientDid: json['recipient_did'] as String,
      recipientDeviceId: json['recipient_device_id'] as String,
      ciphertextType: json['ciphertext_type'] as String,
      ciphertext: json['ciphertext'] as String,
      protocolVersion: json['protocol_version'] as String,
      createdAt: createdAt is String ? DateTime.parse(createdAt).toUtc() : null,
    );
  }
}

class MessengerRelayException implements Exception {
  final int statusCode;
  final String? error;
  final String? message;
  final Map<String, dynamic> body;

  const MessengerRelayException({
    required this.statusCode,
    required this.body,
    this.error,
    this.message,
  });

  @override
  String toString() {
    final label = error ?? 'messenger_relay_error';
    final detail = message == null ? '' : ': $message';
    return 'MessengerRelayException($statusCode $label$detail)';
  }
}

class MessengerRelayClient {
  final Uri relayBaseUrl;
  final http.Client _client;
  final Duration timeout;

  MessengerRelayClient({
    Uri? relayBaseUrl,
    String baseUrl = kDefaultRelayBaseUrl,
    http.Client? client,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : assert(
         client == null || httpClient == null,
         'Pass either client or httpClient, not both.',
       ),
       relayBaseUrl = relayBaseUrl ?? Uri.parse(baseUrl),
       _client = client ?? httpClient ?? http.Client();

  Future<void> publishDevice({
    required String subjectDid,
    required String deviceId,
    required Map<String, Object?> bundle,
    required Map<String, Object?> binding,
    required String bindingSignature,
  }) async {
    await _postJson('/api/v1/messenger/devices', {
      'subject_did': subjectDid,
      'device_id': deviceId,
      'bundle': bundle,
      'binding': binding,
      'binding_signature': bindingSignature,
    });
  }

  Future<void> publishPreKeys({
    required String subjectDid,
    required String deviceId,
    required List<Map<String, Object?>> preKeys,
    required String requestSignature,
  }) async {
    await _postJson('/api/v1/messenger/pre-keys', {
      'subject_did': subjectDid,
      'device_id': deviceId,
      'pre_keys': preKeys,
      'request_signature': requestSignature,
    });
  }

  Future<MessengerPreKeyBundleResponse> fetchPreKeyBundle(
    String subjectDid,
  ) async {
    final body = await _getJson(
      '/api/v1/messenger/pre-key-bundles/${Uri.encodeComponent(subjectDid)}',
    );
    return MessengerPreKeyBundleResponse.fromJson(body);
  }

  Future<MessengerDeviceAvailabilityResponse> fetchDeviceAvailability(
    String subjectDid,
  ) async {
    final body = await _getJson(
      '/api/v1/messenger/devices/${Uri.encodeComponent(subjectDid)}',
    );
    return MessengerDeviceAvailabilityResponse.fromJson(body);
  }

  Future<void> sendMessage({
    required String messageId,
    required String senderDid,
    required String senderDeviceId,
    required String recipientDid,
    required String recipientDeviceId,
    required String ciphertextType,
    required String ciphertext,
    required String protocolVersion,
    required DateTime createdAt,
    required String requestSignature,
  }) async {
    await _postJson('/api/v1/messenger/messages', {
      'message_id': messageId,
      'sender_did': senderDid,
      'sender_device_id': senderDeviceId,
      'recipient_did': recipientDid,
      'recipient_device_id': recipientDeviceId,
      'ciphertext_type': ciphertextType,
      'ciphertext': ciphertext,
      'protocol_version': protocolVersion,
      'created_at': createdAt.toUtc().toIso8601String(),
      'request_signature': requestSignature,
    });
  }

  Future<MessengerMailboxResponse> pullMailbox({
    required String recipientDid,
    required String recipientDeviceId,
    required String requestSignature,
    String? cursor,
  }) async {
    final query = {
      'recipient_did': recipientDid,
      'recipient_device_id': recipientDeviceId,
      'request_signature': requestSignature,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final body = await _getJson('/api/v1/messenger/messages', query: query);
    return MessengerMailboxResponse.fromJson(body);
  }

  Future<void> ackMessage({
    required String messageId,
    required String recipientDid,
    required String recipientDeviceId,
    required String requestSignature,
  }) async {
    await _postJson(
      '/api/v1/messenger/messages/${Uri.encodeComponent(messageId)}/ack',
      {
        'recipient_did': recipientDid,
        'recipient_device_id': recipientDeviceId,
        'request_signature': requestSignature,
      },
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _client
        .get(_endpoint(path, query), headers: AnsibleProtocol.headers)
        .timeout(timeout);
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response.statusCode, body);
    }
    return body;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: const {
            'content-type': 'application/json',
            ...AnsibleProtocol.headers,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final decoded = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _toException(response.statusCode, decoded);
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String responseBody) {
    if (responseBody.trim().isEmpty) return {};
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Expected JSON object from messenger relay');
  }

  MessengerRelayException _toException(
    int statusCode,
    Map<String, dynamic> body,
  ) {
    return MessengerRelayException(
      statusCode: statusCode,
      body: body,
      error: body['error'] as String?,
      message: body['message'] as String?,
    );
  }

  Uri _endpoint(String path, [Map<String, String>? query]) {
    final basePath = relayBaseUrl.path.endsWith('/')
        ? relayBaseUrl.path.substring(0, relayBaseUrl.path.length - 1)
        : relayBaseUrl.path;
    return relayBaseUrl.replace(path: '$basePath$path', queryParameters: query);
  }

  void close() {
    _client.close();
  }
}
