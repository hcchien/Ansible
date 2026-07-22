import 'package:http/http.dart' as http;

import '../config/app_environment.dart';

/// Probes whether the VC issuer can actually issue right now
/// (`GET /readyz` → 200 means the TW provider adapter is configured).
///
/// UX review P1 ("trust-gated upgrade CTA dead-end"): while the production
/// issuer is fail-closed, the 升級驗證 CTA must show an honest 「即將開放」
/// state instead of walking the user into a wizard that cannot finish.
/// Unreachable counts as not-ready — the wizard would dead-end either way.
class IssuerReadinessProbe {
  IssuerReadinessProbe({
    String? issuerBaseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _baseUri = Uri.parse(issuerBaseUrl ?? AppEnvironment.issuerBaseUrl),
       _client = client ?? http.Client();

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  /// Process-lifetime shared instance so screens don't re-probe on every
  /// build; ready flips require an app restart, which matches how issuer
  /// deployment changes roll out.
  static IssuerReadinessProbe shared = IssuerReadinessProbe();

  Future<bool>? _cached;

  /// True when the issuer reports ready (can issue credentials). Cached
  /// after the first successful probe; a failed/negative probe is also
  /// cached — the CTA states "coming soon", not an error.
  Future<bool> isReady() {
    return _cached ??= _probe();
  }

  Future<bool> _probe() async {
    try {
      final basePath = _baseUri.path.endsWith('/')
          ? _baseUri.path.substring(0, _baseUri.path.length - 1)
          : _baseUri.path;
      final response = await _client
          .get(_baseUri.replace(path: '$basePath/readyz'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
