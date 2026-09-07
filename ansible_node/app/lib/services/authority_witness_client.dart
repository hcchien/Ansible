import 'dart:convert';
import 'dart:math';
import 'package:ansible_did/ansible_did.dart';
import 'package:crypto/crypto.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:http/http.dart' as http;
import '../config/app_environment.dart';
import '../config/protocol.dart';

/// Separate, configured AppView observer. Never accepts its URL from Relay data.
/// An empty URL is local/unindexed mode; strict AppViews still reject operations
/// without a checkpoint. This never silently falls back to Relay as a witness.
class AuthorityWitnessClient {
  AuthorityWitnessClient({
    String baseUrl = AppEnvironment.appViewBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _baseUrl = baseUrl,
       _client = client ?? http.Client();
  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;
  bool get enabled => _baseUrl.isNotEmpty;

  Uri _uri(String base, String path) {
    final uri = Uri.parse(base);
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                ['localhost', '127.0.0.1', '::1'].contains(uri.host)))) {
      throw StateError('authority_witness_requires_secure_origin');
    }
    return uri.replace(path: '${uri.path.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, [
    Map<String, Object?>? body,
  ]) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(AnsibleProtocol.headers);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final streamed = await _client.send(request).timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in streamed.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > 1048576) {
        throw StateError('authority_response_too_large');
      }
    }
    if (streamed.statusCode != 200 && streamed.statusCode != 202) {
      throw StateError(
        'authority_witness_not_acknowledged:${streamed.statusCode}',
      );
    }
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  Future<void> checkpointFromRelay({
    required String relayBaseUrl,
    required String did,
    IdentityAnchor? expectedAnchor,
    String? expectedPublicKeyHex,
  }) async {
    if (!enabled) return;
    final List<dynamic> chain;
    if (expectedAnchor != null && expectedAnchor.prevAnchorCid == null) {
      chain = [expectedAnchor.toCanonicalMap()];
    } else {
      final response = await _request(
        'GET',
        _uri(
          relayBaseUrl,
          '/api/v1/identity/chain/${Uri.encodeComponent(did)}',
        ),
      );
      chain = response['anchors'] as List<dynamic>;
    }
    if (chain.isEmpty ||
        chain.length > 128 ||
        (expectedPublicKeyHex != null &&
            (chain.last as Map)['identity_key'] != expectedPublicKeyHex) ||
        (expectedAnchor != null &&
            IdentityAnchor.fromMap(
                  (chain.last as Map).cast<String, dynamic>(),
                ).computeCid() !=
                expectedAnchor.computeCid())) {
      throw StateError('authority_chain_does_not_match_local_anchor');
    }
    final response = await _request(
      'POST',
      _uri(_baseUrl, '/api/v1/authority/checkpoint'),
      {'did': did, 'chain': chain},
    );
    if (response['sequence'] is! int || (response['sequence'] as int) < 1) {
      throw StateError('authority_checkpoint_not_acknowledged');
    }
  }

  /// Start the independent recovery clock when the app starts its pending
  /// recovery, so an honest Relay and observer can serve the same grace period.
  Future<void> announceRecovery({
    required String relayBaseUrl,
    required String did,
    required Map<String, Object?> candidate,
  }) async {
    if (!enabled) return;
    final response = await _request(
      'GET',
      _uri(relayBaseUrl, '/api/v1/identity/chain/${Uri.encodeComponent(did)}'),
    );
    final chain = response['anchors'] as List<dynamic>;
    await _request('POST', _uri(_baseUrl, '/api/v1/authority/checkpoint'), {
      'did': did,
      'chain': chain,
    });
    final result = await _request(
      'POST',
      _uri(_baseUrl, '/api/v1/authority/checkpoint'),
      {
        'did': did,
        'chain': [...chain, candidate],
      },
    );
    if (result['state'] != 'pending' && result['sequence'] is! int) {
      throw StateError('recovery_observer_not_acknowledged');
    }
  }

  Future<int> revalidatePublicHistory(
    List<OpsQueueEntry> entries, {
    required String did,
    required DidSigner signer,
  }) async {
    if (!enabled) throw StateError('authority_witness_not_configured');
    var count = 0;
    for (final entry in entries) {
      if (entry.authorDid != did ||
          !['sent', 'synced'].contains(entry.status)) {
        continue;
      }
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(base64.decode(entry.payload)));
      } on FormatException {
        continue;
      }
      if (decoded is! Map ||
          !['public', 'unlisted'].contains(decoded['visibility'])) {
        continue;
      }
      final operation = <String, Object?>{
        'author_did': entry.authorDid,
        'entity_id': entry.entityId,
        'entity_type': entry.entityType,
        'op_id': entry.opId,
        'op_type': entry.opType,
        'payload': entry.payload,
      };
      final digest = sha256
          .convert(
            utf8.encode('${_canonical(operation)}\u0000${entry.signature}'),
          )
          .toString();
      final authorization = <String, Object?>{
        'type': 'io.trisaura.authorizeHistoricalOperation',
        'version': 1,
        'subject_did': did,
        'op_id': entry.opId,
        'operation_digest': digest,
        'observer_origin': Uri.parse(_baseUrl).origin,
        'issued_at': DateTime.now().toUtc().toIso8601String(),
        'nonce': base64Url
            .encode(List.generate(24, (_) => Random.secure().nextInt(256)))
            .replaceAll('=', ''),
      };
      final signature = await signer.sign(
        utf8.encode(_canonical(authorization)),
      );
      final response = await _request(
        'POST',
        _uri(_baseUrl, '/api/v1/authority/revalidate'),
        {
          'operation': {...operation, 'signature': entry.signature},
          'authorization': authorization,
          'did_signature': signature.hex,
        },
      );
      if (response['revalidated'] != true) {
        throw StateError('history_not_acknowledged');
      }
      count++;
    }
    return count;
  }

  static String _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonical).join(',')}]';
    return jsonEncode(value);
  }

  Future<void> veto({
    required String did,
    required String cid,
    required String signature,
    String? canonicalBody,
  }) async {
    if (!enabled) return;
    final response =
        await _request('POST', _uri(_baseUrl, '/api/v1/authority/veto'), {
          'did': did,
          'pending_anchor_cid': cid,
          'veto_sig': signature,
          'canonical_body': canonicalBody,
        });
    if (response['vetoed'] != true) {
      throw StateError('authority_veto_not_acknowledged');
    }
  }

  Future<void> revoke(Map<String, Object?> revocation, String signature) async {
    if (!enabled) return;
    final response = await _request(
      'POST',
      _uri(_baseUrl, '/api/v1/authority/revoke'),
      {'revocation': revocation, 'did_signature': signature},
    );
    if (response['revoked'] != true) {
      throw StateError('authority_revocation_not_acknowledged');
    }
  }
}
