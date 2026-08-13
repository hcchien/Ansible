import 'package:local_auth/local_auth.dart';

abstract class UserPresenceVerifier {
  Future<bool> verify({required String reason});
}

/// Confirms that the person currently holding the device may perform a
/// sensitive operation. This is device authentication (biometric or device
/// passcode), not a claim that the account belongs to a unique human.
class LocalDeviceUserPresenceVerifier implements UserPresenceVerifier {
  LocalDeviceUserPresenceVerifier({LocalAuthentication? localAuthentication})
    : _localAuthentication = localAuthentication ?? LocalAuthentication();

  final LocalAuthentication _localAuthentication;

  @override
  Future<bool> verify({required String reason}) async {
    try {
      if (!await _localAuthentication.isDeviceSupported()) return false;
      final hasBiometrics = await _localAuthentication.canCheckBiometrics;
      return _localAuthentication.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          // A device with enrolled biometrics must not fall through to a
          // second passcode prompt. Passcode is only the single fallback.
          biometricOnly: hasBiometrics,
          stickyAuth: true,
        ),
      );
    } on Object {
      return false;
    }
  }
}
