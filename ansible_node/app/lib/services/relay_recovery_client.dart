import 'dart:convert';
import 'dart:math';

import 'package:ansible_store/ansible_store.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/app_environment.dart';
import 'identity_anchor_service.dart';

class RecoveryCodeStatus {
  const RecoveryCodeStatus({required this.configured, required this.remaining});
  final bool configured;
  final int remaining;
}

class RecoveryAuditEvent {
  const RecoveryAuditEvent({
    required this.eventType,
    required this.reasonCode,
    required this.occurredAt,
    this.state,
  });
  final String eventType;
  final String reasonCode;
  final DateTime occurredAt;
  final String? state;
}

class RelayRecoveryClient {
  RelayRecoveryClient({Uri? baseUrl, http.Client? httpClient})
    : _baseUrl = baseUrl ?? Uri.parse(AppEnvironment.defaultRelayBaseUrl),
      _http = httpClient ?? http.Client();

  final Uri _baseUrl;
  final http.Client _http;

  Future<List<AnchorDeviceRecord>> devices(String did) async {
    final json = await _get(
      '/api/v1/identity/anchor/${Uri.encodeComponent(did)}/devices',
    );
    final raw = (json['devices'] as List?) ?? const [];
    return raw
        .map(
          (value) => AnchorDeviceRecord.fromMap(
            (value as Map).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
  }

  Future<RecoveryCodeStatus> codeStatus(String did) async {
    final json = await _get(
      '/api/v1/identity/recovery-codes/${Uri.encodeComponent(did)}/status',
    );
    return RecoveryCodeStatus(
      configured: json['configured'] == true,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<RecoveryAuditEvent>> audit(String did) async {
    final json = await _get(
      '/api/v1/identity/anchor/${Uri.encodeComponent(did)}/audit',
    );
    return ((json['events'] as List?) ?? const [])
        .map((value) {
          final event = (value as Map).cast<String, Object?>();
          return RecoveryAuditEvent(
            eventType: event['event_type']! as String,
            reasonCode: event['reason_code']! as String,
            occurredAt: DateTime.parse(
              event['occurred_at']! as String,
            ).toLocal(),
            state: event['state'] as String?,
          );
        })
        .toList(growable: false);
  }

  Future<RecoveryCodeStatus> configureCodes({
    required String did,
    required List<String> codes,
    IdentityKey identityKey = const ActiveIdentityKey(),
  }) async {
    final generatedAt = DateTime.now().toUtc().toIso8601String();
    final hashes = <Map<String, Object?>>[
      for (var index = 0; index < codes.length; index += 1)
        {
          'id': 'code-${index + 1}',
          'hash': recoveryCodeHash(did, codes[index]),
          'hint': normalizedRecoveryCode(codes[index]).substring(0, 4),
        },
    ];
    final unsigned = <String, Object?>{
      'type': 'io.trisaura.identity.recoveryCodes',
      'version': 1,
      'did': did,
      'generated_at': generatedAt,
      'code_hashes': hashes,
    };
    final signature = await identityKey.sign(utf8.encode(jsonEncode(unsigned)));
    final json = await _post('/api/v1/identity/recovery-codes', {
      ...unsigned,
      'signature': signature,
    });
    return RecoveryCodeStatus(
      configured: json['configured'] == true,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, Object?>> _get(String path) async {
    final response = await _http.get(_baseUrl.resolve(path));
    return _decode(response);
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _http.post(
      _baseUrl.resolve(path),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    final json = (decoded as Map).cast<String, Object?>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(json['error']?.toString() ?? 'recovery_request_failed');
    }
    return json;
  }

  static List<String> generateCodes({int count = 10, Random? random}) {
    final source = random ?? Random.secure();
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    return List.generate(count, (_) {
      final raw = List.generate(
        20,
        (_) => alphabet[source.nextInt(alphabet.length)],
      ).join();
      return [
        raw.substring(0, 5),
        raw.substring(5, 10),
        raw.substring(10, 15),
        raw.substring(15),
      ].join('-');
    }, growable: false);
  }
}

String normalizedRecoveryCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');

String recoveryCodeHash(String did, String code) => sha256
    .convert(
      utf8.encode(
        'elix-recovery-code-v1\u0000$did\u0000${normalizedRecoveryCode(code)}',
      ),
    )
    .toString();
