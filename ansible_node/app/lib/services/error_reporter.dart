import 'package:flutter/foundation.dart';

/// A single, backend-agnostic seam for crash / error reporting.
///
/// The app deliberately does NOT bundle a specific crash-reporting SaaS
/// (Sentry, Crashlytics, …) or embed any DSN/API key. Instead every uncaught
/// error is funneled through [ErrorReporter.instance.report]. By default that is
/// a [LoggingErrorReporter], which only logs (via `debugPrint`) and never phones
/// home — so a stock build has no telemetry.
///
/// ── Plugging in a real backend ────────────────────────────────────────────
/// An operator who wants remote error reporting implements [ErrorReporter] with
/// their vendor's SDK and installs it once, early in `main()`:
///
/// ```dart
/// ErrorReporter.instance = MySentryErrorReporter(dsn: myDsn);
/// ```
///
/// Gate it on your own build-time flag if you want it enabled only for
/// production, e.g.:
///
/// ```dart
/// const enableReporting = bool.fromEnvironment('ANSIBLE_ENABLE_ERROR_REPORTING');
/// if (enableReporting) {
///   ErrorReporter.instance = MySentryErrorReporter(dsn: ...);
/// }
/// ```
///
/// The wiring in `main.dart` (FlutterError.onError, PlatformDispatcher.onError,
/// and runZonedGuarded) already routes every uncaught error here, so no other
/// call sites change when a real reporter is installed.
abstract class ErrorReporter {
  /// The active reporter. Defaults to a no-op logging reporter. Replace this
  /// once, early in startup, to enable a real backend (see class docs).
  static ErrorReporter instance = const LoggingErrorReporter();

  const ErrorReporter();

  /// Report an uncaught error.
  ///
  /// [fatal] indicates the error prevented normal operation (e.g. a startup
  /// failure) as opposed to a recoverable/logged Flutter framework error.
  /// [context] is a short human label for where the error came from.
  void report(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? context,
  });
}

/// Default reporter: logs and does nothing else. No network, no telemetry.
class LoggingErrorReporter extends ErrorReporter {
  const LoggingErrorReporter();

  @override
  void report(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? context,
  }) {
    final label = context == null ? '' : ' [$context]';
    debugPrint('${fatal ? 'FATAL' : 'ERROR'}$label: $error');
    if (stack != null) {
      debugPrint(stack.toString());
    }
  }
}
