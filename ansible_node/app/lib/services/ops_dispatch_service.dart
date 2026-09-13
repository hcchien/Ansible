import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';

import '../config/app_environment.dart';
import 'op_signature_payload.dart';
import 'relay_ops_client.dart';
import 'delivery_diagnostics.dart';

class OpsDispatchSummary {
  const OpsDispatchSummary({
    this.sent = 0,
    this.rejected = 0,
    this.retryPending = 0,
    this.retryReason,
    this.rejectionReasons = const [],
  });

  final int sent;
  final int rejected;
  final int retryPending;
  final String? retryReason;
  final List<String> rejectionReasons;

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

  Future<OpsQueueEntry> signAndEnqueue(
    OpsQueueEntry entry, {
    bool persistBeforeSigning = true,
  }) async {
    // A cancelled reaction toggle keeps its previous visible choice. Composed
    // posts instead survive authorization cancellation as a durable draft op.
    if (!persistBeforeSigning) {
      final signed = (await sign(entry)).copyWith(status: 'pending');
      await repository.enqueue(signed);
      return signed;
    }
    if (repository case final DriftOpsQueueRepository drift) {
      final current = await drift.retainForAuthorization(entry);
      if (current.authorDid != entry.authorDid ||
          ['cancelled', 'rejected'].contains(current.status)) {
        throw StateError('operation_not_retryable');
      }
      if (current.status == 'synced') return current;
      entry = current;
    } else {
      await repository.enqueue(
        entry.copyWith(status: 'awaiting_authorization'),
      );
    }
    final signed = (await sign(entry)).copyWith(status: 'pending');
    if (repository is DriftOpsQueueRepository) {
      if (!await (repository as DriftOpsQueueRepository).prepareRetry(signed)) {
        throw StateError('operation_cancelled');
      }
    } else {
      await repository.enqueue(signed);
    }
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
    return dispatchEntries(entries);
  }

  Future<OpsDispatchSummary> dispatchEntries(
    List<OpsQueueEntry> entries,
  ) async {
    var sent = 0;
    var rejected = 0;
    final rejectionReasons = <String>[];

    for (final entry in entries) {
      try {
        if (repository case final DriftOpsQueueRepository drift) {
          if (!await drift.claimForSend(entry.opId)) continue;
        } else {
          await repository.markSent(entry.opId);
        }
        await DeliveryDiagnostics.shared.record(
          entry,
          relayClient.baseUri,
          'attempting',
        );
        await relayClient.ingest(entry);
        await repository.markSynced(entry.opId);
        await DeliveryDiagnostics.shared.record(
          entry,
          relayClient.baseUri,
          'accepted',
        );
        sent += 1;
      } on RelayOpsException catch (error) {
        await DeliveryDiagnostics.shared.record(
          entry,
          relayClient.baseUri,
          error.isDuplicate ? 'accepted' : 'failed',
          reason: error.error ?? 'relay_request_failed',
        );
        if (error.isDuplicate) {
          await repository.markSynced(entry.opId);
          sent += 1;
          continue;
        }
        if (error.isPermanentRejection) {
          await repository.markRejected(entry.opId);
          rejected += 1;
          rejectionReasons.add('${entry.opId}: ${error.toString()}');
          continue;
        }
        if (error.isPolicyBlock) {
          await repository.markBlocked(entry.opId);
          return OpsDispatchSummary(
            sent: sent,
            rejected: rejected,
            retryPending: 1,
            retryReason: error.toString(),
            rejectionReasons: rejectionReasons,
          );
        }
        if (!error.isPermanentRejection) {
          // A temporary server failure must stay explicitly retryable.  A
          // manual sync moves blocked operations back to pending before
          // dispatching them again.
          await repository.markBlocked(entry.opId);
        }
        return OpsDispatchSummary(
          sent: sent,
          rejected: rejected,
          retryPending: 1,
          retryReason: error.toString(),
          rejectionReasons: rejectionReasons,
        );
      } catch (error) {
        await DeliveryDiagnostics.shared.record(
          entry,
          relayClient.baseUri,
          'failed',
          reason: 'network_or_authorization_failed',
        );
        // Network, TLS, and request-header failures happen before a Relay
        // response exists.  Preserve both the operation and the diagnostic
        // for the explicit retry boundary in the next manual sync.
        await repository.markBlocked(entry.opId);
        return OpsDispatchSummary(
          sent: sent,
          rejected: rejected,
          retryPending: 1,
          retryReason: error.toString(),
          rejectionReasons: rejectionReasons,
        );
      }
    }
    return OpsDispatchSummary(
      sent: sent,
      rejected: rejected,
      rejectionReasons: rejectionReasons,
    );
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
