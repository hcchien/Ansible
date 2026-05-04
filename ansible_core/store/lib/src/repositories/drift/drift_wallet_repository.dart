import 'package:drift/drift.dart';

import '../../db/app_database.dart';
import '../../entities/wallet_credential.dart' as credential_entity;
import '../../entities/wallet_presentation.dart' as presentation_entity;
import '../wallet_repository.dart';

class DriftWalletRepository implements WalletRepository {
  final AppDatabase _db;

  DriftWalletRepository(this._db);

  @override
  Future<void> saveCredential({
    required credential_entity.WalletCredential metadata,
    required String encryptedPayload,
    required String encryptionVersion,
  }) async {
    await _db.transaction(() async {
      await _db
          .into(_db.walletCredentials)
          .insert(
            WalletCredentialsCompanion.insert(
              credentialId: metadata.credentialId,
              issuerDid: metadata.issuerDid,
              holderDid: metadata.holderDid,
              credentialType: metadata.credentialType,
              status: metadata.status.name,
              validFrom: metadata.validFrom,
              validUntil: metadata.validUntil,
              displayName: metadata.displayName,
              createdAt: Value(metadata.createdAt),
              updatedAt: Value(metadata.updatedAt),
            ),
            mode: InsertMode.insertOrReplace,
          );

      await _db
          .into(_db.walletCredentialPayloads)
          .insert(
            WalletCredentialPayloadsCompanion.insert(
              credentialId: metadata.credentialId,
              encryptedPayload: encryptedPayload,
              encryptionVersion: encryptionVersion,
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
  }

  @override
  Future<credential_entity.WalletCredential?> getCredential(
    String credentialId,
  ) async {
    final row =
        await (_db.select(_db.walletCredentials)
              ..where((table) => table.credentialId.equals(credentialId)))
            .getSingleOrNull();
    if (row == null) return null;
    return _mapCredential(row);
  }

  @override
  Future<String?> getEncryptedPayload(String credentialId) async {
    final row =
        await (_db.select(_db.walletCredentialPayloads)
              ..where((table) => table.credentialId.equals(credentialId)))
            .getSingleOrNull();
    return row?.encryptedPayload;
  }

  @override
  Future<List<credential_entity.WalletCredential>> listCredentials() async {
    final rows = await (_db.select(
      _db.walletCredentials,
    )..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])).get();
    return rows.map(_mapCredential).toList();
  }

  @override
  Future<void> updateCredentialStatus(
    String credentialId,
    credential_entity.WalletCredentialStatus status, {
    DateTime? updatedAt,
  }) async {
    await (_db.update(
      _db.walletCredentials,
    )..where((table) => table.credentialId.equals(credentialId))).write(
      WalletCredentialsCompanion(
        status: Value(status.name),
        updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
      ),
    );
  }

  @override
  Future<void> deleteCredential(String credentialId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.walletPresentations,
      )..where((table) => table.credentialId.equals(credentialId))).go();
      await (_db.delete(
        _db.walletCredentialPayloads,
      )..where((table) => table.credentialId.equals(credentialId))).go();
      await (_db.delete(
        _db.walletCredentials,
      )..where((table) => table.credentialId.equals(credentialId))).go();
    });
  }

  @override
  Future<void> recordPresentation(
    presentation_entity.WalletPresentation presentation,
  ) async {
    await _db
        .into(_db.walletPresentations)
        .insert(
          WalletPresentationsCompanion.insert(
            presentationId: presentation.presentationId,
            credentialId: presentation.credentialId,
            verifierAudience: presentation.verifierAudience,
            nonceHash: presentation.nonceHash,
            result: presentation.result.name,
            createdAt: Value(presentation.createdAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<List<presentation_entity.WalletPresentation>> listPresentations(
    String credentialId,
  ) async {
    final rows =
        await (_db.select(_db.walletPresentations)
              ..where((table) => table.credentialId.equals(credentialId))
              ..orderBy([(table) => OrderingTerm.desc(table.createdAt)]))
            .get();
    return rows.map(_mapPresentation).toList();
  }

  credential_entity.WalletCredential _mapCredential(WalletCredential row) {
    return credential_entity.WalletCredential(
      credentialId: row.credentialId,
      issuerDid: row.issuerDid,
      holderDid: row.holderDid,
      credentialType: row.credentialType,
      status: credential_entity.WalletCredentialStatus.parse(row.status),
      validFrom: row.validFrom,
      validUntil: row.validUntil,
      displayName: row.displayName,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  presentation_entity.WalletPresentation _mapPresentation(
    WalletPresentation row,
  ) {
    return presentation_entity.WalletPresentation(
      presentationId: row.presentationId,
      credentialId: row.credentialId,
      verifierAudience: row.verifierAudience,
      nonceHash: row.nonceHash,
      result: presentation_entity.WalletPresentationResult.parse(row.result),
      createdAt: row.createdAt,
    );
  }
}
