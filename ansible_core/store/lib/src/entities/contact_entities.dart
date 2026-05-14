enum ContactRelationship {
  following,
  follower,
  mutual,
  conversation,
  boardPeer,
  invite,
  manual,
  unknown,
  blocked;

  static ContactRelationship parse(String value) {
    return ContactRelationship.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown ContactRelationship "$value"');
      },
    );
  }
}

enum ContactTrustState {
  known,
  changed,
  unverified,
  blocked;

  static ContactTrustState parse(String value) {
    return ContactTrustState.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown ContactTrustState "$value"');
      },
    );
  }
}

enum MessengerAvailability {
  available,
  noDevices,
  noPreKeys,
  blocked,
  unresolved,
  relayUnavailable;

  static MessengerAvailability parse(String value) {
    return MessengerAvailability.values.firstWhere(
      (item) => item.name == value,
      orElse: () {
        throw ArgumentError('Unknown MessengerAvailability "$value"');
      },
    );
  }
}

class ContactRecord {
  final String subjectDid;
  final String? handle;
  final String? displayName;
  final String? localAlias;
  final String? avatarUrl;
  final ContactRelationship relationship;
  final String source;
  final ContactTrustState trustState;
  final MessengerAvailability messengerAvailability;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastResolvedAt;

  const ContactRecord({
    required this.subjectDid,
    this.handle,
    this.displayName,
    this.localAlias,
    this.avatarUrl,
    this.relationship = ContactRelationship.unknown,
    this.source = 'unknown',
    this.trustState = ContactTrustState.unverified,
    this.messengerAvailability = MessengerAvailability.unresolved,
    required this.createdAt,
    required this.updatedAt,
    this.lastResolvedAt,
  });

  String get label {
    final alias = localAlias?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final resolvedHandle = handle?.trim();
    if (resolvedHandle != null && resolvedHandle.isNotEmpty) {
      return resolvedHandle;
    }
    return shortDid;
  }

  String get shortDid {
    if (subjectDid.length <= 18) return subjectDid;
    return '${subjectDid.substring(0, 10)}...'
        '${subjectDid.substring(subjectDid.length - 6)}';
  }

  ContactRecord copyWith({
    String? subjectDid,
    String? handle,
    String? displayName,
    String? localAlias,
    String? avatarUrl,
    ContactRelationship? relationship,
    String? source,
    ContactTrustState? trustState,
    MessengerAvailability? messengerAvailability,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastResolvedAt,
  }) {
    return ContactRecord(
      subjectDid: subjectDid ?? this.subjectDid,
      handle: handle ?? this.handle,
      displayName: displayName ?? this.displayName,
      localAlias: localAlias ?? this.localAlias,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      relationship: relationship ?? this.relationship,
      source: source ?? this.source,
      trustState: trustState ?? this.trustState,
      messengerAvailability:
          messengerAvailability ?? this.messengerAvailability,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastResolvedAt: lastResolvedAt ?? this.lastResolvedAt,
    );
  }
}
