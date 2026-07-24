import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';

/// Wallet-only holder-binding key. It is deliberately distinct from the DID
/// content key and from Issuer/board administrative keys.
abstract interface class HolderBindingKey {
  Future<IdentityPublicKey> ensureKey();
  Future<IdentitySignature> sign(
    List<int> message, {
    bool reuseAuthenticationContext = false,
  });
}

class WalletHolderKeyService implements HolderBindingKey {
  WalletHolderKeyService({HardwarePurposeKey? key})
    : _key = key ?? HardwarePurposeKey(HardwareKeyPurpose.walletHolderBinding);

  final HardwarePurposeKey _key;

  @override
  Future<IdentityPublicKey> ensureKey() async =>
      await _key.load() ?? await _key.generate();

  Future<IdentitySignature> signCanonicalJson(String canonicalJson) async {
    await ensureKey();
    return _key.sign(utf8.encode(canonicalJson));
  }

  @override
  Future<IdentitySignature> sign(
    List<int> message, {
    bool reuseAuthenticationContext = false,
  }) async {
    await ensureKey();
    return _key.sign(
      message,
      reuseAuthenticationContext: reuseAuthenticationContext,
    );
  }
}

/// Holder binding for a single board. This is intentionally not the global
/// Wallet holder key: presenting credentials for two boards must not expose a
/// stable public key or DID that lets their hosts correlate the member.
class BoardHolderKeyService implements HolderBindingKey {
  BoardHolderKeyService({
    required String boardId,
    HardwareScopedPurposeKey? key,
  }) : _key =
           key ??
           HardwareScopedPurposeKey(
             HardwareKeyPurpose.boardHolderBinding,
             context: boardId,
           );

  final HardwareScopedPurposeKey _key;

  @override
  Future<IdentityPublicKey> ensureKey() async =>
      await _key.load() ?? await _key.generate();

  @override
  Future<IdentitySignature> sign(
    List<int> message, {
    bool reuseAuthenticationContext = false,
  }) async {
    await ensureKey();
    return _key.sign(
      message,
      reuseAuthenticationContext: reuseAuthenticationContext,
    );
  }

  Future<void> delete() => _key.delete();
}

/// Root administration uses another hardware alias and is unavailable on
/// reduced-trust platforms (currently Windows and Linux). Callers must surface that limitation
/// instead of silently falling back to an exportable key.
class IssuerRootAdminKeyService {
  IssuerRootAdminKeyService({HardwarePurposeKey? key})
    : _key =
          key ??
          HardwarePurposeKey(HardwareKeyPurpose.issuerRootAdministration);

  final HardwarePurposeKey _key;

  Future<IdentityPublicKey> ensureHardwareKey() async {
    final publicKey = await _key.load() ?? await _key.generate();
    if (publicKey.custody != IdentityKeyCustody.hardware) {
      throw StateError('Issuer root administration requires hardware custody.');
    }
    return publicKey;
  }

  Future<IdentitySignature> approve(List<int> canonicalPayload) async {
    await ensureHardwareKey();
    return _key.sign(canonicalPayload);
  }
}
