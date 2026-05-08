enum ContextPackPurpose {
  murmurToNote,
  noteToDiscussion,
  discussionSummary,
  followingSummary,
  boardSummary;

  static ContextPackPurpose parse(String value) {
    return ContextPackPurpose.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown ContextPackPurpose "$value"'),
    );
  }
}

enum ContextPrivacyLevel {
  publicOnly,
  containsPrivate,
  containsSensitive;

  static ContextPrivacyLevel parse(String value) {
    return ContextPrivacyLevel.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown ContextPrivacyLevel "$value"'),
    );
  }
}

class ContextPack {
  final String id;
  final ContextPackPurpose purpose;
  final String sourceRefsJson;
  final String snapshotJson;
  final ContextPrivacyLevel privacyLevel;
  final bool allowedRemote;
  final String createdByDid;
  final DateTime createdAt;

  const ContextPack({
    required this.id,
    required this.purpose,
    required this.sourceRefsJson,
    required this.snapshotJson,
    required this.privacyLevel,
    required this.allowedRemote,
    required this.createdByDid,
    required this.createdAt,
  });
}
