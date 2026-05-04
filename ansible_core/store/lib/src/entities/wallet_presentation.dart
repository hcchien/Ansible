enum WalletPresentationResult {
  approved,
  denied,
  failed;

  static WalletPresentationResult parse(String value) {
    return WalletPresentationResult.values.firstWhere(
      (result) => result.name == value,
      orElse: () =>
          throw ArgumentError('Unknown wallet presentation result "$value"'),
    );
  }
}

class WalletPresentation {
  final String presentationId;
  final String credentialId;
  final String verifierAudience;
  final String nonceHash;
  final WalletPresentationResult result;
  final DateTime createdAt;

  WalletPresentation({
    required this.presentationId,
    required this.credentialId,
    required this.verifierAudience,
    required this.nonceHash,
    required this.result,
    required this.createdAt,
  });
}
