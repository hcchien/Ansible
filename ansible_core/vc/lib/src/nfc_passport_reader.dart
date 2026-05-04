import 'dart:async';

import 'passport_data.dart';

/// Abstract interface for ePassport NFC reading.
///
/// NFC hardware reading is **deferred to Q3**. The only concrete
/// implementation currently shipped is [MockNfcPassportReader], which
/// returns a synthetic [PassportData] instantly and is used for all
/// development, simulator, and CI runs.
///
/// When real NFC support is added (ICAO 9303 BAC/PACE + APDU over
/// `nfc_manager`), it will be registered behind this interface so the
/// rest of the app requires no changes.
abstract class NfcPassportReader {
  /// Start a passport NFC scan.
  ///
  /// [onPassportRead] is called once a [PassportData] is ready.
  /// [onError] is called with a user-readable message on failure.
  Future<void> scan({
    required void Function(PassportData) onPassportRead,
    required void Function(String) onError,
  });

  /// Cancel an in-progress scan.  Safe to call when no scan is running.
  Future<void> cancel();

  /// Always returns `false` until Q3 NFC implementation is wired in.
  static Future<bool> isAvailable() async => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mock implementation  (all environments until Q3)
// ─────────────────────────────────────────────────────────────────────────────

/// A [NfcPassportReader] that returns a synthetic [PassportData] instantly.
///
/// Used in:
///   - All current builds (NFC hardware support deferred to Q3)
///   - Flutter widget tests and integration tests on simulators
///   - CI pipelines
///
/// The mock passport uses a fixed ICAO-specimen TD3 MRZ so the
/// `passportSecret` is deterministic and test vectors can rely on it.
class MockNfcPassportReader implements NfcPassportReader {
  /// Simulated scan delay.  Defaults to 800 ms to exercise the UI spinner.
  final Duration delay;

  /// When non-null, [scan] calls [onError] with this message instead of
  /// delivering a successful [PassportData].  Useful for testing error UI.
  final String? simulateError;

  const MockNfcPassportReader({
    this.delay = const Duration(milliseconds: 800),
    this.simulateError,
  });

  // ── Fixed mock passport data ─────────────────────────────────────────────
  //
  // TD3 MRZ — fictitious ICAO specimen passport:
  //   Line 1 (44 chars): P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<
  //   Line 2 (44 chars): L898902C36UTO6908061F9406236ZE184226B<<<<<1
  //
  static const _mockMrzLine1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<';
  static const _mockMrzLine2 = 'L898902C36UTO6908061F9406236ZE184226B<<<<<1';

  PassportData _buildMockData() {
    final base = PassportData.fromMrz(_mockMrzLine1, _mockMrzLine2);
    return PassportData(
      documentNumber: base.documentNumber,
      dateOfBirth: base.dateOfBirth,
      dateOfExpiry: base.dateOfExpiry,
      nationality: base.nationality,
      dg1Bytes: _buildMockDg1(_mockMrzLine1 + _mockMrzLine2),
      sodBytes: List.filled(32, 0xAB), // placeholder SOD
      passportSecret: base.passportSecret,
    );
  }

  /// Wrap an 88-byte MRZ string in a minimal DG1 TLV structure.
  List<int> _buildMockDg1(String mrz) {
    final mrzBytes = mrz.codeUnits;
    final inner = [0x5F, 0x1F, mrzBytes.length, ...mrzBytes];
    return [0x61, inner.length, ...inner];
  }

  @override
  Future<void> scan({
    required void Function(PassportData) onPassportRead,
    required void Function(String) onError,
  }) async {
    await Future<void>.delayed(delay);
    if (simulateError != null) {
      onError(simulateError!);
    } else {
      onPassportRead(_buildMockData());
    }
  }

  @override
  Future<void> cancel() async {
    // Nothing to cancel for a mock reader.
  }
}
