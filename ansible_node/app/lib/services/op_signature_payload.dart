import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';

class OpSignaturePayload {
  static String fromQueueEntry(OpsQueueEntry entry) {
    return fromFields(
      opId: entry.opId,
      authorDid: entry.authorDid,
      entityType: entry.entityType,
      entityId: entry.entityId,
      opType: entry.opType,
      payload: entry.payload,
    );
  }

  static String fromFields({
    required String opId,
    required String authorDid,
    required String entityType,
    required String entityId,
    required String opType,
    required String payload,
  }) {
    return _canonicalJson({
      'author_did': authorDid,
      'entity_id': entityId,
      'entity_type': entityType,
      'op_id': opId,
      'op_type': opType,
      'payload': payload,
    });
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return '{${entries.map((entry) {
        return '${jsonEncode(entry.key.toString())}:${_canonicalJson(entry.value)}';
      }).join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}
