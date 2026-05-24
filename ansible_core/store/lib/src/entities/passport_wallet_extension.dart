class PassportWalletExtension {
  final String credentialId;
  final String passportLocalUniqueId;
  final String nationalIdHash;
  final String passportNumberHash;
  final String nationality;
  final String assuranceMethod;
  final DateTime verifiedAt;

  const PassportWalletExtension({
    required this.credentialId,
    required this.passportLocalUniqueId,
    required this.nationalIdHash,
    required this.passportNumberHash,
    required this.nationality,
    required this.assuranceMethod,
    required this.verifiedAt,
  });

  Map<String, Object?> toJson() => {
    'credentialId': credentialId,
    'passportLocalUniqueId': passportLocalUniqueId,
    'nationalIdHash': nationalIdHash,
    'passportNumberHash': passportNumberHash,
    'nationality': nationality,
    'assuranceMethod': assuranceMethod,
    'verifiedAt': verifiedAt.toUtc().toIso8601String(),
  };
}
