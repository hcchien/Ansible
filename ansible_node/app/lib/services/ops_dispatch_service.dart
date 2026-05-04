import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';

import 'relay_ops_client.dart';

class OpsDispatchService {
  final OpsQueueRepository repository;
  final DidSigner signer;
  final RelayOpsClient relayClient;

  OpsDispatchService({
    required this.repository,
    DidSigner? signer,
    RelayOpsClient? relayClient,
  }) : signer = signer ?? DidSignerImpl(),
       relayClient = relayClient ?? RelayOpsClient();

  Future<OpsQueueEntry> signAndEnqueue(OpsQueueEntry entry) async {
    final signed = await sign(entry);
    await repository.enqueue(signed);
    return signed;
  }

  Future<OpsQueueEntry> sign(OpsQueueEntry entry) async {
    final message = utf8.encode(entry.opId + entry.payload);

    try {
      final signature = await signer.sign(message);
      return entry.copyWith(signature: signature.hex);
    } on UnimplementedError {
      return entry.copyWith(signature: _devSignature(entry));
    } on StateError {
      return entry.copyWith(signature: _devSignature(entry));
    }
  }

  Future<void> flushPending({int limit = 25}) async {
    final entries = await repository.listPending(limit: limit);

    for (final entry in entries) {
      try {
        await relayClient.ingest(entry);
        await repository.markSent(entry.opId);
        await repository.markSynced(entry.opId);
      } on RelayOpsException catch (error) {
        if (error.isDuplicate) {
          await repository.markSynced(entry.opId);
          continue;
        }
        if (error.isPermanentRejection) {
          await repository.markRejected(entry.opId);
          continue;
        }
        break;
      } catch (_) {
        break;
      }
    }
  }

  String _devSignature(OpsQueueEntry entry) {
    final bytes = utf8.encode('${entry.opId}:${entry.payload}');
    return 'dev-${base64Url.encode(bytes).replaceAll('=', '')}';
  }
}
