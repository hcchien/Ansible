import '../entities/wallet_credential.dart';
import '../entities/wallet_presentation.dart';
import '../entities/passport_wallet_extension.dart';

abstract class WalletRepository {
  Future<void> saveCredential({
    required WalletCredential metadata,
    required String encryptedPayload,
    required String encryptionVersion,
  });

  Future<WalletCredential?> getCredential(String credentialId);

  Future<String?> getEncryptedPayload(String credentialId);

  Future<List<WalletCredential>> listCredentials();

  Future<void> updateCredentialStatus(
    String credentialId,
    WalletCredentialStatus status, {
    DateTime? updatedAt,
  });

  Future<void> deleteCredential(String credentialId);

  Future<void> recordPresentation(WalletPresentation presentation);

  Future<List<WalletPresentation>> listPresentations(String credentialId);

  Future<void> savePassportExtension(PassportWalletExtension extension);

  Future<PassportWalletExtension?> getPassportExtensionByLocalUniqueId(
    String passportLocalUniqueId,
  );

  Future<PassportWalletExtension?> getPassportExtensionForCredential(
    String credentialId,
  );
}
