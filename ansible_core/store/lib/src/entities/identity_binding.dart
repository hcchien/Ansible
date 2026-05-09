enum IdentityBindingType {
  nostr,
  activityPub,
  nip05,
  atproto;

  static IdentityBindingType parse(String value) {
    return IdentityBindingType.values.firstWhere(
      (item) => item.name == value,
      orElse: () => throw ArgumentError('Unknown IdentityBindingType "$value"'),
    );
  }
}

class IdentityBinding {
  final String bindingId;
  final String localAccountDid;
  final IdentityBindingType bindingType;
  final String identifier;
  final String? publicKey;
  final bool isPrimary;
  final DateTime createdAt;
  final DateTime updatedAt;

  const IdentityBinding({
    required this.bindingId,
    required this.localAccountDid,
    required this.bindingType,
    required this.identifier,
    required this.createdAt,
    required this.updatedAt,
    this.publicKey,
    this.isPrimary = false,
  });
}
