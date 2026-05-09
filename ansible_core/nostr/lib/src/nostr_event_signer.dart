import 'nostr_event.dart';
import 'nostr_key_store.dart';

abstract class NostrEventSigner {
  Future<NostrEvent> sign(NostrEventDraft draft);
}

abstract class NostrSigningBridge {
  Future<String> signEventId({
    required String privateKeyHex,
    required String eventIdHex,
  });
}

class UnavailableNostrEventSigner implements NostrEventSigner {
  @override
  Future<NostrEvent> sign(NostrEventDraft draft) async {
    throw StateError(
      'Production Nostr signing is unavailable. Configure a real secp256k1 '
      'Schnorr signer before publishing events.',
    );
  }
}

class ProductionNostrEventSigner implements NostrEventSigner {
  final NostrKeyStore keyStore;
  final NostrSigningBridge signingBridge;

  const ProductionNostrEventSigner({
    required this.keyStore,
    required this.signingBridge,
  });

  @override
  Future<NostrEvent> sign(NostrEventDraft draft) async {
    final key = await keyStore.read();
    if (key == null) {
      throw StateError('No local Nostr key material found.');
    }
    if (key.publicKeyHex != draft.pubkey.toLowerCase()) {
      throw StateError('Nostr draft pubkey does not match local key material.');
    }

    final eventId = draft.computeId();
    final signatureHex = await signingBridge.signEventId(
      privateKeyHex: key.privateKeyHex,
      eventIdHex: eventId,
    );
    if (!NostrSignaturePolicy.isProductionSignature(signatureHex)) {
      throw StateError(
        'Native Nostr signing returned an invalid or development signature.',
      );
    }

    return NostrEvent(
      id: eventId,
      pubkey: draft.pubkey,
      createdAt: draft.createdAt,
      kind: draft.kind,
      tags: draft.tags,
      content: draft.content,
      sig: signatureHex.toLowerCase(),
    );
  }
}

class TestOnlyNostrEventSigner implements NostrEventSigner {
  final String signatureHex;

  const TestOnlyNostrEventSigner({required this.signatureHex});

  @override
  Future<NostrEvent> sign(NostrEventDraft draft) async {
    if (!NostrSignaturePolicy.isProductionSignature(signatureHex)) {
      throw ArgumentError('Nostr event signature must be a real 64-byte hex');
    }
    return NostrEvent(
      id: draft.computeId(),
      pubkey: draft.pubkey,
      createdAt: draft.createdAt,
      kind: draft.kind,
      tags: draft.tags,
      content: draft.content,
      sig: signatureHex,
    );
  }
}

class NostrSignaturePolicy {
  static bool isProductionSignature(String signatureHex) {
    final lower = signatureHex.toLowerCase();
    if (lower.startsWith('dev') ||
        lower.startsWith('stub') ||
        lower.startsWith('deadbeef') ||
        lower.contains('stub')) {
      return false;
    }
    return RegExp(r'^[0-9a-f]{128}$').hasMatch(lower);
  }
}
