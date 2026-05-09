import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/content_item.dart' as content;
import '../../entities/identity_binding.dart' as identity;
import '../../entities/publication_intent.dart' as intent_entity;
import '../../entities/publication_target.dart' as target_entity;
import '../publication_repository.dart';

class DriftPublicationRepository implements PublicationRepository {
  final AppDatabase _db;

  DriftPublicationRepository(this._db);

  @override
  Future<void> enqueueIntent(
    intent_entity.PublicationIntent intent, {
    List<target_entity.PublicationTarget> targets = const [],
  }) async {
    _validateIntent(intent);
    for (final target in targets) {
      if (target.intentId != intent.intentId) {
        throw ArgumentError('Publication target must reference intent id');
      }
    }

    await _db.transaction(() async {
      await _db
          .into(_db.publicationIntents)
          .insertOnConflictUpdate(
            PublicationIntentsCompanion.insert(
              intentId: intent.intentId,
              authorDid: intent.authorDid,
              contentItemId: intent.contentItemId,
              action: intent.action.name,
              visibility: intent.visibility.name,
              distributionPreference: intent.distributionPreference.name,
              status: Value(intent.status.name),
              payloadHash: Value(intent.payloadHash),
              signature: Value(intent.signature),
              signatureScheme: Value(intent.signatureScheme),
              signedAt: Value(intent.signedAt),
              createdAt: Value(intent.createdAt),
              updatedAt: Value(intent.updatedAt),
              error: Value(intent.error),
            ),
          );

      for (final target in targets) {
        await _db
            .into(_db.publicationTargets)
            .insertOnConflictUpdate(
              PublicationTargetsCompanion.insert(
                targetId: target.targetId,
                intentId: target.intentId,
                protocol: target.protocol.name,
                endpoint: target.endpoint,
                status: Value(target.status.name),
                remoteId: Value(target.remoteId),
                lastAttemptAt: Value(target.lastAttemptAt),
                error: Value(target.error),
              ),
            );
      }
    });
  }

  @override
  Future<intent_entity.PublicationIntent?> getIntentById(
    String intentId,
  ) async {
    final row = await (_db.select(
      _db.publicationIntents,
    )..where((table) => table.intentId.equals(intentId))).getSingleOrNull();
    return row == null ? null : _mapIntent(row);
  }

  @override
  Future<target_entity.PublicationTarget?> getTargetById(
    String targetId,
  ) async {
    final row = await (_db.select(
      _db.publicationTargets,
    )..where((table) => table.targetId.equals(targetId))).getSingleOrNull();
    return row == null ? null : _mapTarget(row);
  }

  @override
  Future<List<target_entity.PublicationTarget>> listTargets({
    target_entity.PublicationProtocol? protocol,
    intent_entity.PublicationStatus? status,
    int limit = 50,
  }) async {
    final query = _db.select(_db.publicationTargets)
      ..orderBy([(table) => OrderingTerm.asc(table.targetId)])
      ..limit(limit);
    if (protocol != null) {
      query.where((table) => table.protocol.equals(protocol.name));
    }
    if (status != null) {
      query.where((table) => table.status.equals(status.name));
    }
    final rows = await query.get();
    return rows.map(_mapTarget).toList();
  }

  @override
  Future<List<target_entity.PublicationTarget>> listTargetsForIntent(
    String intentId,
  ) async {
    final rows =
        await (_db.select(_db.publicationTargets)
              ..where((table) => table.intentId.equals(intentId))
              ..orderBy([(table) => OrderingTerm.asc(table.targetId)]))
            .get();
    return rows.map(_mapTarget).toList();
  }

  @override
  Future<List<target_entity.PublicationTarget>> listPendingTargets({
    target_entity.PublicationProtocol? protocol,
    int limit = 50,
  }) async {
    final query = _db.select(_db.publicationTargets)
      ..where((table) => table.status.equals('pending'))
      ..orderBy([(table) => OrderingTerm.asc(table.targetId)]);
    if (protocol != null) {
      query.where((table) => table.protocol.equals(protocol.name));
    }

    final rows = await query.get();
    final publishable = <target_entity.PublicationTarget>[];
    for (final row in rows) {
      final intent = await getIntentById(row.intentId);
      if (intent != null && intent.canDistribute) {
        publishable.add(_mapTarget(row));
      }
      if (publishable.length >= limit) break;
    }
    return publishable;
  }

  @override
  Future<void> markTargetPublished(String targetId, {String? remoteId}) async {
    await (_db.update(
      _db.publicationTargets,
    )..where((table) => table.targetId.equals(targetId))).write(
      PublicationTargetsCompanion(
        status: const Value('published'),
        remoteId: Value(remoteId),
        lastAttemptAt: Value(DateTime.now().toUtc()),
        error: const Value(null),
      ),
    );
  }

  @override
  Future<void> markTargetFailed(String targetId, String error) async {
    await (_db.update(
      _db.publicationTargets,
    )..where((table) => table.targetId.equals(targetId))).write(
      PublicationTargetsCompanion(
        status: const Value('failed'),
        lastAttemptAt: Value(DateTime.now().toUtc()),
        error: Value(error),
      ),
    );
  }

  @override
  Future<void> resetTargetForRetry(String targetId) async {
    await (_db.update(
      _db.publicationTargets,
    )..where((table) => table.targetId.equals(targetId))).write(
      PublicationTargetsCompanion(
        status: const Value('pending'),
        lastAttemptAt: const Value(null),
        error: const Value(null),
      ),
    );
  }

  @override
  Future<void> markIntentComplete(String intentId) async {
    await (_db.update(
      _db.publicationIntents,
    )..where((table) => table.intentId.equals(intentId))).write(
      PublicationIntentsCompanion(
        status: const Value('complete'),
        updatedAt: Value(DateTime.now().toUtc()),
        error: const Value(null),
      ),
    );
  }

  @override
  Future<void> saveIdentityBinding(identity.IdentityBinding binding) async {
    await _db
        .into(_db.identityBindings)
        .insertOnConflictUpdate(
          IdentityBindingsCompanion.insert(
            bindingId: binding.bindingId,
            localAccountDid: binding.localAccountDid,
            bindingType: binding.bindingType.name,
            identifier: binding.identifier,
            publicKey: Value(binding.publicKey),
            isPrimary: Value(binding.isPrimary),
            createdAt: Value(binding.createdAt),
            updatedAt: Value(binding.updatedAt),
          ),
        );
  }

  @override
  Future<List<identity.IdentityBinding>> bindingsForAccount(
    String localAccountDid,
  ) async {
    final rows =
        await (_db.select(_db.identityBindings)
              ..where((table) => table.localAccountDid.equals(localAccountDid))
              ..orderBy([
                (table) => OrderingTerm.desc(table.isPrimary),
                (table) => OrderingTerm.asc(table.createdAt),
              ]))
            .get();
    return rows.map(_mapBinding).toList();
  }

  intent_entity.PublicationIntent _mapIntent(PublicationIntent row) {
    return intent_entity.PublicationIntent(
      intentId: row.intentId,
      authorDid: row.authorDid,
      contentItemId: row.contentItemId,
      action: intent_entity.PublicationAction.parse(row.action),
      visibility: content.ContentVisibility.parse(row.visibility),
      distributionPreference: intent_entity.DistributionPreference.parse(
        row.distributionPreference,
      ),
      status: intent_entity.PublicationStatus.parse(row.status),
      payloadHash: row.payloadHash,
      signature: row.signature,
      signatureScheme: row.signatureScheme,
      signedAt: row.signedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      error: row.error,
    );
  }

  target_entity.PublicationTarget _mapTarget(PublicationTarget row) {
    return target_entity.PublicationTarget(
      targetId: row.targetId,
      intentId: row.intentId,
      protocol: target_entity.PublicationProtocol.parse(row.protocol),
      endpoint: row.endpoint,
      status: intent_entity.PublicationStatus.parse(row.status),
      remoteId: row.remoteId,
      lastAttemptAt: row.lastAttemptAt,
      error: row.error,
    );
  }

  identity.IdentityBinding _mapBinding(IdentityBinding row) {
    return identity.IdentityBinding(
      bindingId: row.bindingId,
      localAccountDid: row.localAccountDid,
      bindingType: identity.IdentityBindingType.parse(row.bindingType),
      identifier: row.identifier,
      publicKey: row.publicKey,
      isPrimary: row.isPrimary,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  void _validateIntent(intent_entity.PublicationIntent intent) {
    if (intent.visibility == content.ContentVisibility.private) {
      throw ArgumentError('Private content cannot create publication intents');
    }
  }
}
