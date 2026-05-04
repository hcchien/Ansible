enum WalletCredentialStatus {
  active,
  expired,
  revoked,
  suspended,
  deleted;

  static WalletCredentialStatus parse(String value) {
    return WalletCredentialStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () =>
          throw ArgumentError('Unknown wallet credential status "$value"'),
    );
  }
}

class WalletCredential {
  final String credentialId;
  final String issuerDid;
  final String holderDid;
  final String credentialType;
  final WalletCredentialStatus status;
  final DateTime validFrom;
  final DateTime validUntil;
  final String displayName;
  final DateTime createdAt;
  final DateTime updatedAt;

  WalletCredential({
    required this.credentialId,
    required this.issuerDid,
    required this.holderDid,
    required this.credentialType,
    required this.status,
    required this.validFrom,
    required this.validUntil,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  WalletCredential copyWith({
    WalletCredentialStatus? status,
    DateTime? updatedAt,
  }) {
    return WalletCredential(
      credentialId: credentialId,
      issuerDid: issuerDid,
      holderDid: holderDid,
      credentialType: credentialType,
      status: status ?? this.status,
      validFrom: validFrom,
      validUntil: validUntil,
      displayName: displayName,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
