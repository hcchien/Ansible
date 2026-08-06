import 'dart:convert';

import 'package:http/http.dart' as http;

import 'board_access_presentation_service.dart';
import 'private_board_crypto_service.dart';

class PrivateBoardDeviceKey {
  const PrivateBoardDeviceKey({
    required this.deviceKeyId,
    required this.publicKeyHex,
    required this.publicKeyHash,
    required this.policyVersion,
  });

  final String deviceKeyId;
  final String publicKeyHex;
  final String publicKeyHash;
  final int policyVersion;

  factory PrivateBoardDeviceKey.fromJson(Map<String, Object?> json) =>
      PrivateBoardDeviceKey(
        deviceKeyId: _string(json, 'device_key_id'),
        publicKeyHex: _string(json, 'agreement_public_key_hex'),
        publicKeyHash: _string(json, 'public_key_hash'),
        policyVersion: json['policy_version'] as int,
      );
}

class PrivateBoardKeyClient {
  PrivateBoardKeyClient({
    required this.forumHost,
    required this.boardId,
    required this.access,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final Uri forumHost;
  final String boardId;
  final BoardAccessPresentationService access;
  final http.Client _http;

  Uri get _base => forumHost.resolve(
    '/api/v1/forum-host/boards/${Uri.encodeComponent(boardId)}/encryption/',
  );

  Future<PrivateBoardDeviceKey> registerDevice({
    required BoardAccessCapability capability,
    required String publicKeyHex,
    bool reuseAuthenticationContext = false,
  }) async {
    final uri = _base.resolve('device-keys');
    final response = await _http.post(
      uri,
      headers: {
        'content-type': 'application/json',
        ...await access.proofHeaders(
          capability: capability,
          method: 'POST',
          requestUri: uri,
          scope: 'key:read',
          reuseAuthenticationContext: reuseAuthenticationContext,
        ),
      },
      body: jsonEncode({'agreement_public_key_hex': publicKeyHex}),
    );
    final json = _response(response);
    return PrivateBoardDeviceKey.fromJson(
      Map<String, Object?>.from(json['device_key'] as Map),
    );
  }

  Future<List<PrivateBoardDeviceKey>> listDevices({
    required BoardAccessCapability capability,
  }) async {
    final uri = _base.resolve('device-keys');
    final response = await _http.get(
      uri,
      headers: await access.proofHeaders(
        capability: capability,
        method: 'GET',
        requestUri: uri,
        scope: 'moderate',
      ),
    );
    final devices = _response(response)['devices'];
    if (devices is! List) throw const BoardAccessException('invalid_response');
    return devices
        .map(
          (value) => PrivateBoardDeviceKey.fromJson(
            Map<String, Object?>.from(value as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<BoardEpochKeyEnvelope> currentEnvelope({
    required BoardAccessCapability capability,
    bool reuseAuthenticationContext = false,
  }) async {
    final uri = _base.resolve('epochs/current/envelope');
    final response = await _http.get(
      uri,
      headers: await access.proofHeaders(
        capability: capability,
        method: 'GET',
        requestUri: uri,
        scope: 'key:read',
        reuseAuthenticationContext: reuseAuthenticationContext,
      ),
    );
    return BoardEpochKeyEnvelope.fromJson(
      Map<String, Object?>.from(_response(response)['envelope'] as Map),
    );
  }

  Future<void> activateEpoch({
    required BoardAccessCapability capability,
    required int epoch,
    required int policyVersion,
    required List<BoardEpochKeyEnvelope> envelopes,
  }) async {
    final uri = _base.resolve('epochs');
    final response = await _http.post(
      uri,
      headers: {
        'content-type': 'application/json',
        ...await access.proofHeaders(
          capability: capability,
          method: 'POST',
          requestUri: uri,
          scope: 'moderate',
        ),
      },
      body: jsonEncode({
        'epoch': epoch,
        'policy_version': policyVersion,
        'envelopes': envelopes.map((value) => value.toJson()).toList(),
      }),
    );
    _response(response);
  }

  Future<void> revokeDevice({
    required BoardAccessCapability capability,
    required String deviceKeyId,
  }) async {
    final uri = _base.resolve(
      'device-keys/${Uri.encodeComponent(deviceKeyId)}/revoke',
    );
    final response = await _http.post(
      uri,
      headers: await access.proofHeaders(
        capability: capability,
        method: 'POST',
        requestUri: uri,
        scope: 'moderate',
      ),
    );
    _response(response);
  }

  Map<String, Object?> _response(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const BoardAccessException('invalid_response');
    final json = Map<String, Object?>.from(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BoardAccessException(
        json['error']?.toString() ?? 'private_board_key_request_failed',
        statusCode: response.statusCode,
      );
    }
    return json;
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const BoardAccessException('invalid_response');
  }
  return value;
}
