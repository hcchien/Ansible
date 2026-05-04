import '../../entities/wallet_credential.dart';
import '../../entities/wallet_presentation.dart';
import '../wallet_repository.dart';

class InMemoryWalletRepository implements WalletRepository {
  final Map<String, WalletCredential> _credentials = {};
  final Map<String, String> _payloads = {};
  final List<WalletPresentation> _presentations = [];

  InMemoryWalletRepository();

  InMemoryWalletRepository.withCredentials(List<WalletCredential> credentials) {
    for (final credential in credentials) {
      _credentials[credential.credentialId] = credential;
    }
  }

  @override
  Future<void> saveCredential({
    required WalletCredential metadata,
    required String encryptedPayload,
    required String encryptionVersion,
  }) async {
    _credentials[metadata.credentialId] = metadata;
    _payloads[metadata.credentialId] = encryptedPayload;
  }

  @override
  Future<WalletCredential?> getCredential(String credentialId) async {
    return _credentials[credentialId];
  }

  @override
  Future<String?> getEncryptedPayload(String credentialId) async {
    return _payloads[credentialId];
  }

  @override
  Future<List<WalletCredential>> listCredentials() async {
    final values = _credentials.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return values;
  }

  @override
  Future<void> updateCredentialStatus(
    String credentialId,
    WalletCredentialStatus status, {
    DateTime? updatedAt,
  }) async {
    final credential = _credentials[credentialId];
    if (credential == null) return;
    _credentials[credentialId] = credential.copyWith(
      status: status,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> deleteCredential(String credentialId) async {
    _credentials.remove(credentialId);
    _payloads.remove(credentialId);
    _presentations.removeWhere(
      (presentation) => presentation.credentialId == credentialId,
    );
  }

  @override
  Future<void> recordPresentation(WalletPresentation presentation) async {
    _presentations.add(presentation);
  }

  @override
  Future<List<WalletPresentation>> listPresentations(
    String credentialId,
  ) async {
    return _presentations
        .where((presentation) => presentation.credentialId == credentialId)
        .toList();
  }
}
