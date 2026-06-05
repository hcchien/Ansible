/// A cached reputation tier for an author DID.
class DidReputation {
  final String did;
  final String tier;
  final DateTime updatedAt;

  const DidReputation({
    required this.did,
    required this.tier,
    required this.updatedAt,
  });
}
