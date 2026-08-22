import 'identity_anchor.dart';

/// Result of verifying a hash-chained sequence of [IdentityAnchor]s.
class AnchorChainVerification {
  final bool isValid;

  /// Machine-readable failure code, null when [isValid].
  final AnchorChainError? error;

  /// Index (0-based, genesis first) of the anchor that failed, when applicable.
  final int? failedAtIndex;

  /// Human-readable detail (not for end users; for logs/tests).
  final String? detail;

  const AnchorChainVerification.valid()
    : isValid = true,
      error = null,
      failedAtIndex = null,
      detail = null;

  const AnchorChainVerification.invalid(
    this.error, {
    this.failedAtIndex,
    this.detail,
  }) : isValid = false;

  @override
  String toString() => isValid
      ? 'AnchorChainVerification.valid'
      : 'AnchorChainVerification.invalid($error @ $failedAtIndex: $detail)';
}

enum AnchorChainError {
  empty,
  genesisNotInitial,
  brokenLink,
  missingSignature,
  badReason,
  nonGenesisMissingPrev,
  schemaVersionUnsupported,
  invalidGenesisCommitment,
  genesisCommitmentChanged,
  didMismatch,
}

/// Verifies that an ordered list of anchors (genesis first, newest last) forms
/// a sound hash chain.
///
/// What is checked in this FOUNDATION slice (design "Properties"):
///   - first anchor is `reason: initial` with `prev_anchor_cid == null`;
///   - every subsequent anchor's `prev_anchor_cid` equals the CID
///     (`sha256:` of the canonical body) of the immediately preceding anchor;
///   - every anchor carries a (non-empty) `sig`;
///   - every `reason` is a known reason code;
///   - schema_version is supported.
///
/// TODO(Task 4, relay) / TODO(Task 1, rust/core): cryptographic verification
/// that [IdentityAnchor.sig] is a valid Ed25519 signature by `identity_key`
/// over the canonical body — and that recovery/rotation anchors carry the
/// required co-signature / recovery_proof — is deferred. This round verifies
/// chain *structure*, signature *presence*, and reason validity only.
class IdentityAnchorChain {
  const IdentityAnchorChain._();

  static AnchorChainVerification verify(List<IdentityAnchor> anchors) {
    if (anchors.isEmpty) {
      return const AnchorChainVerification.invalid(AnchorChainError.empty);
    }

    Map<String, Object?>? v1Commitment;

    for (var i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];

      if (anchor.schemaVersion > IdentityAnchor.currentSchemaVersion) {
        return AnchorChainVerification.invalid(
          AnchorChainError.schemaVersionUnsupported,
          failedAtIndex: i,
          detail:
              'schema_version ${anchor.schemaVersion} > '
              '${IdentityAnchor.currentSchemaVersion}',
        );
      }

      if (anchor.schemaVersion >= 4) {
        final commitment = anchor.genesisCommitment;
        try {
          if (commitment == null ||
              commitment['method'] != 'did:elix' ||
              commitment['method_version'] != 1) {
            throw const FormatException();
          }
          final expectedDid = deriveDidElixV1(
            genesisKey: commitment['genesis_key'] as String? ?? '',
            genesisNonceHex: commitment['genesis_nonce'] as String? ?? '',
          );
          if (expectedDid != anchor.did) {
            return AnchorChainVerification.invalid(
              AnchorChainError.didMismatch,
              failedAtIndex: i,
            );
          }
          if (i == 0 && commitment['genesis_key'] != anchor.identityKey) {
            return const AnchorChainVerification.invalid(
              AnchorChainError.invalidGenesisCommitment,
              failedAtIndex: 0,
            );
          }
          if (v1Commitment != null &&
              !_sameCommitment(v1Commitment, commitment)) {
            return AnchorChainVerification.invalid(
              AnchorChainError.genesisCommitmentChanged,
              failedAtIndex: i,
            );
          }
          v1Commitment ??= commitment;
        } catch (_) {
          return AnchorChainVerification.invalid(
            AnchorChainError.invalidGenesisCommitment,
            failedAtIndex: i,
          );
        }
      } else if (v1Commitment != null) {
        return AnchorChainVerification.invalid(
          AnchorChainError.genesisCommitmentChanged,
          failedAtIndex: i,
        );
      }

      // Signature presence (cryptographic validity deferred — see class doc).
      if (anchor.sig.trim().isEmpty) {
        return AnchorChainVerification.invalid(
          AnchorChainError.missingSignature,
          failedAtIndex: i,
        );
      }

      // Reason validity is enforced by AnchorReason.parse at construction, but
      // re-assert the genesis rule explicitly here.
      if (i == 0) {
        if (anchor.reason != AnchorReason.initial) {
          return AnchorChainVerification.invalid(
            AnchorChainError.genesisNotInitial,
            failedAtIndex: 0,
            detail: 'genesis reason is ${anchor.reason.storageValue}',
          );
        }
        if (anchor.prevAnchorCid != null) {
          return AnchorChainVerification.invalid(
            AnchorChainError.brokenLink,
            failedAtIndex: 0,
            detail: 'genesis must have null prev_anchor_cid',
          );
        }
      } else {
        if (anchor.prevAnchorCid == null) {
          return AnchorChainVerification.invalid(
            AnchorChainError.nonGenesisMissingPrev,
            failedAtIndex: i,
          );
        }
        final expectedPrev = anchors[i - 1].computeCid();
        if (anchor.prevAnchorCid != expectedPrev) {
          return AnchorChainVerification.invalid(
            AnchorChainError.brokenLink,
            failedAtIndex: i,
            detail:
                'prev_anchor_cid ${anchor.prevAnchorCid} != '
                'expected $expectedPrev',
          );
        }
      }
    }

    return const AnchorChainVerification.valid();
  }

  static bool _sameCommitment(
    Map<String, Object?> expected,
    Map<String, Object?> actual,
  ) {
    return expected['method'] == actual['method'] &&
        expected['method_version'] == actual['method_version'] &&
        expected['genesis_key'] == actual['genesis_key'] &&
        expected['genesis_nonce'] == actual['genesis_nonce'];
  }
}
