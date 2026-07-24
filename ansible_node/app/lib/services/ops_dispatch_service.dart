import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';

import '../config/app_environment.dart';
import 'op_signature_payload.dart';
import 'relay_ops_client.dart';

class OpsDispatchSummary {
  const OpsDispatchSummary({
    this.sent = 0,
    this.rejected = 0,
    this.retryPending = 0,
  });

  final int sent;
  final int rejected;
  final int retryPending;

  bool get hasActivity => sent > 0 || rejected > 0 || retryPending > 0;
}

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
    final message = utf8.encode(OpSignaturePayload.fromQueueEntry(entry));

    try {
      final signature = await signer.sign(message);
      return entry.copyWith(signature: signature.hex);
    } on UnimplementedError catch (error) {
      return _signWithInsecureFallbackIfAllowed(entry, error);
    } on StateError catch (error) {
      return _signWithInsecureFallbackIfAllowed(entry, error);
    }
  }

  Future<OpsDispatchSummary> flushPending({int limit = 25}) async {
    final entries = await repository.listPending(limit: limit);
    var sent = 0;
    var rejected = 0;

    for (final entry in entries) {
      try {
        await relayClient.ingest(entry);
        await repository.markSent(entry.opId);
        await repository.markSynced(entry.opId);
        sent += 1;
      } on RelayOpsException catch (error) {
        if (error.isDuplicate) {
          await repository.markSynced(entry.opId);
          sent += 1;
          continue;
        }
        if (error.isPermanentRejection) {
          await repository.markRejected(entry.opId);
          rejected += 1;
          continue;
        }
        if (error.isPolicyBlock) {
          await repository.markBlocked(entry.opId);
          return OpsDispatchSummary(
            sent: sent,
            rejected: rejected,
            retryPending: 1,
          );
        }
        if (error.isRetryable) {
          // A temporary server failure must stay explicitly retryable.  A
          // manual sync moves blocked operations back to pending before
          // dispatching them again.
          await repository.markBlocked(entry.opId);
        }
        return OpsDispatchSummary(
          sent: sent,
          rejected: rejected,
          retryPending: 1,
        );
      } catch (_) {
        return OpsDispatchSummary(
          sent: sent,
          rejected: rejected,
          retryPending: 1,
        );
      }
    }
    return OpsDispatchSummary(sent: sent, rejected: rejected);
  }

  String _devSignature(OpsQueueEntry entry) {
    final bytes = utf8.encode('${entry.opId}:${entry.payload}');
    return 'dev-${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  OpsQueueEntry _signWithInsecureFallbackIfAllowed(
    OpsQueueEntry entry,
    Object error,
  ) {
    if (AppEnvironment.allowInsecureSigningFallback) {
      return entry.copyWith(signature: _devSignature(entry));
    }

    throw StateError(
      'DID signing failed and insecure signing fallback is disabled: $error',
    );
  }
}
