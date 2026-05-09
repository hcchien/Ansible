import 'publication_intent.dart';

enum PublicationProtocol {
  nostr,
  activityPub;

  static PublicationProtocol parse(String value) {
    return PublicationProtocol.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown PublicationProtocol "$value"'),
    );
  }
}

class PublicationTarget {
  final String targetId;
  final String intentId;
  final PublicationProtocol protocol;
  final String endpoint;
  final PublicationStatus status;
  final String? remoteId;
  final DateTime? lastAttemptAt;
  final String? error;

  const PublicationTarget({
    required this.targetId,
    required this.intentId,
    required this.protocol,
    required this.endpoint,
    required this.status,
    this.remoteId,
    this.lastAttemptAt,
    this.error,
  });

  PublicationTarget copyWith({
    PublicationStatus? status,
    String? remoteId,
    DateTime? lastAttemptAt,
    String? error,
  }) {
    return PublicationTarget(
      targetId: targetId,
      intentId: intentId,
      protocol: protocol,
      endpoint: endpoint,
      status: status ?? this.status,
      remoteId: remoteId ?? this.remoteId,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      error: error ?? this.error,
    );
  }
}
