import 'dart:async';

import 'package:ansible_did/ansible_did.dart';

/// A locally authorized sync-signing context.
///
/// The context never contains biometric material or private-key bytes.  It
/// only records whether the platform can reuse the already-approved hardware
/// authentication context for subsequent nonce-bound signatures.
abstract interface class SyncAuthenticationSession {
  bool get reuseHardwareAuthenticationContext;

  Future<void> close();
}

class HardwareSyncAuthenticationSession implements SyncAuthenticationSession {
  HardwareSyncAuthenticationSession(this._session);

  final HardwareAuthenticationSession _session;

  @override
  bool get reuseHardwareAuthenticationContext => true;

  @override
  Future<void> close() => _session.close();
}

/// Test/platform fallback for a successful local presence check that does not
/// expose a reusable Secure Enclave authentication context.
class PresenceOnlySyncAuthenticationSession
    implements SyncAuthenticationSession {
  const PresenceOnlySyncAuthenticationSession();

  @override
  bool get reuseHardwareAuthenticationContext => false;

  @override
  Future<void> close() async {}
}

class SyncAuthorizationGrant {
  SyncAuthorizationGrant._({
    required SyncAuthorizationController owner,
    required int generation,
    required this.reuseHardwareAuthenticationContext,
  }) : _owner = owner,
       _generation = generation;

  final SyncAuthorizationController _owner;
  final int _generation;
  final bool reuseHardwareAuthenticationContext;
  bool _released = false;

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _owner._release(_generation);
  }
}

/// Maintains one short-lived, foreground-only authorization window for sync.
///
/// The window is scoped to a DID and has a fixed lifetime: using it does not
/// extend the expiry.  Every Relay operation still receives an independent
/// nonce-bound signature.  App lifecycle owners must call [invalidate] when
/// the app leaves the foreground; identity changes use the same fail-closed
/// path.
class SyncAuthorizationController {
  SyncAuthorizationController({
    this.validity = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static final SyncAuthorizationController shared =
      SyncAuthorizationController();

  final Duration validity;
  final DateTime Function() _now;

  Future<void> _serial = Future<void>.value();
  SyncAuthenticationSession? _session;
  String? _scope;
  DateTime? _validUntil;
  Timer? _expiryTimer;
  int _generation = 0;
  int _activeGrants = 0;
  bool _closeWhenIdle = false;

  Future<SyncAuthorizationGrant?> acquire({
    required String scope,
    required Future<SyncAuthenticationSession?> Function() authenticate,
  }) {
    return _synchronized(() async {
      final now = _now();
      final validUntil = _validUntil;
      final canReuse =
          _session != null &&
          _scope == scope &&
          validUntil != null &&
          now.isBefore(validUntil) &&
          !_closeWhenIdle;
      if (canReuse) {
        _activeGrants += 1;
        return SyncAuthorizationGrant._(
          owner: this,
          generation: _generation,
          reuseHardwareAuthenticationContext:
              _session!.reuseHardwareAuthenticationContext,
        );
      }

      // Do not replace a native LAContext while an older operation is still
      // using it.  The caller can retry after that operation completes.
      if (_activeGrants > 0) return null;
      await _closeCurrent();

      final session = await authenticate();
      if (session == null) return null;

      _generation += 1;
      _session = session;
      _scope = scope;
      _validUntil = _now().add(validity);
      _activeGrants = 1;
      _closeWhenIdle = false;
      _expiryTimer = Timer(validity, () {
        unawaited(_expire(_generation));
      });
      return SyncAuthorizationGrant._(
        owner: this,
        generation: _generation,
        reuseHardwareAuthenticationContext:
            session.reuseHardwareAuthenticationContext,
      );
    });
  }

  /// Immediately removes a reusable authorization window.
  ///
  /// This is used for backgrounding, device lock/inactive transitions, and
  /// identity changes.  Closing an in-use native context makes any later
  /// signature in that operation fail closed rather than silently extending
  /// authorization after the lifecycle boundary.
  Future<void> invalidate() {
    return _synchronized(() async {
      _generation += 1;
      _activeGrants = 0;
      await _closeCurrent();
    });
  }

  Future<void> _expire(int generation) {
    return _synchronized(() async {
      if (generation != _generation || _session == null) return;
      if (_activeGrants > 0) {
        _closeWhenIdle = true;
        return;
      }
      await _closeCurrent();
    });
  }

  Future<void> _release(int generation) {
    return _synchronized(() async {
      if (generation != _generation) return;
      if (_activeGrants > 0) _activeGrants -= 1;
      final expired = _validUntil == null || !_now().isBefore(_validUntil!);
      if (_activeGrants == 0 && (_closeWhenIdle || expired)) {
        await _closeCurrent();
      }
    });
  }

  Future<void> _closeCurrent() async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final session = _session;
    _session = null;
    _scope = null;
    _validUntil = null;
    _closeWhenIdle = false;
    if (session != null) await session.close();
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
