/// App↔relay/appview protocol version constants (service architecture plan,
/// Phase 0 — API versioning). Mirrors `AnsibleRelay.Protocol` and
/// `AnsibleAppview.Protocol`.
///
/// Every relay/appview HTTP client sends [headers] so servers can enforce a
/// minimum supported version. A `426 {"error": "upgrade_required"}` response
/// means this build is older than the server's minimum and the user must
/// update the app (mapped to friendly copy in lib/l10n/user_facing_error.dart).
class AnsibleProtocol {
  const AnsibleProtocol._();

  /// Highest protocol version this app speaks. Ops with a `schema_version`
  /// above this are unknown future formats and are skipped during sync
  /// instead of being misparsed.
  static const int currentVersion = 1;

  /// Request header carrying the client's protocol version.
  static const String headerName = 'x-ansible-protocol';

  /// Spread into the request headers of every relay/appview HTTP client.
  static const Map<String, String> headers = {headerName: '$currentVersion'};

  /// Server error code accompanying an HTTP 426 when this client is older
  /// than the server's minimum supported protocol version.
  static const String upgradeRequiredCode = 'upgrade_required';
}
