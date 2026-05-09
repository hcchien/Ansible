import 'content_item.dart';

enum PublicationAction {
  publish,
  update,
  delete;

  static PublicationAction parse(String value) {
    return PublicationAction.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown PublicationAction "$value"'),
    );
  }
}

enum PublicationStatus {
  pending,
  published,
  complete,
  failed,
  rejected;

  static PublicationStatus parse(String value) {
    return PublicationStatus.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown PublicationStatus "$value"'),
    );
  }
}

enum DistributionPreference {
  localOnly,
  nostr,
  activityPub,
  nostrAndActivityPub;

  static DistributionPreference parse(String value) {
    return DistributionPreference.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown DistributionPreference "$value"');
      },
    );
  }
}

class PublicationIntent {
  final String intentId;
  final String authorDid;
  final String contentItemId;
  final PublicationAction action;
  final ContentVisibility visibility;
  final DistributionPreference distributionPreference;
  final PublicationStatus status;
  final String? payloadHash;
  final String? signature;
  final String? signatureScheme;
  final DateTime? signedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? error;

  const PublicationIntent({
    required this.intentId,
    required this.authorDid,
    required this.contentItemId,
    required this.action,
    required this.visibility,
    required this.distributionPreference,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.payloadHash,
    this.signature,
    this.signatureScheme,
    this.signedAt,
    this.error,
  });

  bool get hasProductionSignature {
    final sig = signature;
    final scheme = signatureScheme;
    if (sig == null || scheme == null || signedAt == null) return false;
    if (scheme != 'ed25519' && scheme != 'schnorr-secp256k1') return false;

    final lower = sig.toLowerCase();
    if (lower.startsWith('dev') ||
        lower.startsWith('stub') ||
        lower.startsWith('deadbeef') ||
        lower.contains('stub')) {
      return false;
    }

    return RegExp(r'^[0-9a-f]{128}$').hasMatch(lower);
  }

  bool get canDistribute {
    return visibility != ContentVisibility.private && hasProductionSignature;
  }

  PublicationIntent copyWith({
    PublicationStatus? status,
    String? payloadHash,
    String? signature,
    String? signatureScheme,
    DateTime? signedAt,
    DateTime? updatedAt,
    String? error,
  }) {
    return PublicationIntent(
      intentId: intentId,
      authorDid: authorDid,
      contentItemId: contentItemId,
      action: action,
      visibility: visibility,
      distributionPreference: distributionPreference,
      status: status ?? this.status,
      payloadHash: payloadHash ?? this.payloadHash,
      signature: signature ?? this.signature,
      signatureScheme: signatureScheme ?? this.signatureScheme,
      signedAt: signedAt ?? this.signedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      error: error ?? this.error,
    );
  }
}
