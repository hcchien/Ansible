/// Minimal W3C DID Document model.
///
/// Only the fields relevant to Tris-Aura V1.1 are included:
///   - id, verificationMethod (Ed25519 key), authentication
///
/// Full spec: https://www.w3.org/TR/did-core/

class DidVerificationMethod {
  final String id;
  final String type; // "Ed25519VerificationKey2020"
  final String controller;
  final String publicKeyMultibase; // multibase-encoded Ed25519 public key

  const DidVerificationMethod({
    required this.id,
    required this.type,
    required this.controller,
    required this.publicKeyMultibase,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'controller': controller,
    'publicKeyMultibase': publicKeyMultibase,
  };
}

class DidDocument {
  static const context = [
    'https://www.w3.org/ns/did/v1',
    'https://w3id.org/security/suites/ed25519-2020/v1',
  ];

  final String id; // DID string
  final List<DidVerificationMethod> verificationMethod;
  final List<String> authentication; // references into verificationMethod

  const DidDocument({
    required this.id,
    required this.verificationMethod,
    required this.authentication,
  });

  /// Construct a minimal did:key document from a hex-encoded public key.
  factory DidDocument.fromKey(String did, String publicKeyHex) {
    final vmId = '$did#keys-1';
    return DidDocument(
      id: did,
      verificationMethod: [
        DidVerificationMethod(
          id: vmId,
          type: 'Ed25519VerificationKey2020',
          controller: did,
          publicKeyMultibase:
              'z$publicKeyHex', // simplified; real impl uses base58btc
        ),
      ],
      authentication: [vmId],
    );
  }

  Map<String, dynamic> toJson() => {
    '@context': context,
    'id': id,
    'verificationMethod': verificationMethod.map((v) => v.toJson()).toList(),
    'authentication': authentication,
  };
}
