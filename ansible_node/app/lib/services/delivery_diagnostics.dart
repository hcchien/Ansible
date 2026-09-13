import 'dart:convert';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bounded device-local, content-free history. Export is an explicit UI action.
class DeliveryDiagnostics {
  static final shared = DeliveryDiagnostics();
  final FlutterSecureStorage storage;
  DeliveryDiagnostics({this.storage = const FlutterSecureStorage()});
  Future<void>? _pending;
  String _key(String did) =>
      'elix.delivery.v1.${base64Url.encode(utf8.encode(did))}';

  Future<List<Map<String, dynamic>>> read(String did) async {
    await _pending;
    return _read(did);
  }

  Future<List<Map<String, dynamic>>> _read(String did) async {
    final value = await storage.read(key: _key(did));
    return value == null
        ? []
        : (jsonDecode(value) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
  }

  Future<void> record(
    OpsQueueEntry entry,
    Uri service,
    String state, {
    String? reason,
  }) {
    final future = (_pending ?? Future<void>.value())
        .then((_) async {
          final records = await _read(entry.authorDid);
          records.add({
            'op_id': entry.opId,
            'entity_type': entry.entityType,
            'at': DateTime.now().toUtc().toIso8601String(),
            'service': service.host,
            'state': state,
            if (reason != null)
              'reason': RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(reason)
                  ? reason
                  : 'request_failed',
          });
          await storage.write(
            key: _key(entry.authorDid),
            value: jsonEncode(
              records
                  .skip(records.length > 200 ? records.length - 200 : 0)
                  .toList(),
            ),
          );
        })
        .catchError((Object _) {
          // Failure to write diagnostic metadata must not block delivery.
        });
    _pending = future;
    future.then((_) {
      if (identical(_pending, future)) _pending = null;
    });
    return future;
  }
}
