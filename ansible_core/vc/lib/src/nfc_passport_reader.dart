import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'passport_data.dart';

class PassportAccessData {
  const PassportAccessData({
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
  });

  final String documentNumber;
  final String dateOfBirth;
  final String dateOfExpiry;

  String get normalizedDocumentNumber =>
      documentNumber.trim().toUpperCase().padRight(9, '<');

  void validate() {
    if (!RegExp(r'^[A-Z0-9<]{1,9}$').hasMatch(
      documentNumber.trim().toUpperCase(),
    )) {
      throw const FormatException('Invalid passport document number.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(dateOfBirth) ||
        !RegExp(r'^\d{6}$').hasMatch(dateOfExpiry)) {
      throw const FormatException('Passport dates must use YYMMDD.');
    }
  }

  String get mrzKey {
    validate();
    final number = normalizedDocumentNumber;
    return '$number${_checkDigit(number)}'
        '$dateOfBirth${_checkDigit(dateOfBirth)}'
        '$dateOfExpiry${_checkDigit(dateOfExpiry)}';
  }

  static int _checkDigit(String value) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var index = 0; index < value.length; index++) {
      final char = value.codeUnitAt(index);
      final numeric = switch (char) {
        >= 48 && <= 57 => char - 48,
        >= 65 && <= 90 => char - 55,
        _ => 0,
      };
      sum += numeric * weights[index % weights.length];
    }
    return sum % 10;
  }
}

/// Abstract interface for ePassport NFC reading.
abstract class NfcPassportReader {
  /// Start a passport NFC scan.
  ///
  /// [onPassportRead] is called once a [PassportData] is ready.
  /// [onError] is called with a user-readable message on failure.
  Future<void> scan({
    required PassportAccessData accessData,
    required void Function(PassportData) onPassportRead,
    required void Function(String) onError,
  });

  /// Cancel an in-progress scan.  Safe to call when no scan is running.
  Future<void> cancel();

  Future<bool> isAvailable();
}

class PlatformNfcPassportReader implements NfcPassportReader {
  const PlatformNfcPassportReader();

  static const _channel = MethodChannel('elix/passport_nfc');

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isIOS) return false;
    return await _channel.invokeMethod<bool>('isAvailable') ?? false;
  }

  @override
  Future<void> scan({
    required PassportAccessData accessData,
    required void Function(PassportData) onPassportRead,
    required void Function(String) onError,
  }) async {
    try {
      final trustedCscaPem = await rootBundle.loadString(
        'assets/trusted_csca/taiwan.pem',
      );
      final result = await _channel.invokeMapMethod<String, Object?>('scan', {
        'mrz_key': accessData.mrzKey,
        'trusted_csca_pem': trustedCscaPem,
      });
      if (result == null) {
        onError('Passport reader returned no data.');
        return;
      }
      final documentNumber = result['document_number'] as String?;
      final dateOfBirth = result['date_of_birth'] as String?;
      final dateOfExpiry = result['date_of_expiry'] as String?;
      final nationality = result['nationality'] as String?;
      final dg1 = result['dg1'] as Uint8List?;
      final sod = result['sod'] as Uint8List?;
      if (documentNumber == null ||
          dateOfBirth == null ||
          dateOfExpiry == null ||
          nationality == null ||
          dg1 == null ||
          sod == null) {
        onError('Passport reader returned incomplete chip data.');
        return;
      }
      final mrz = (result['mrz'] as String?)?.replaceAll('\n', '') ?? '';
      if (mrz.length != 88) {
        onError('Passport reader returned an invalid TD3 MRZ.');
        return;
      }
      final parsed = PassportData.fromMrz(
        mrz.substring(0, 44),
        mrz.substring(44, 88),
      );
      onPassportRead(
        PassportData(
          documentNumber: documentNumber,
          dateOfBirth: dateOfBirth,
          dateOfExpiry: dateOfExpiry,
          nationality: nationality,
          dg1Bytes: dg1,
          sodBytes: sod,
          passportSecret: parsed.passportSecret,
          sodSignatureVerified:
              result['sod_signature_verified'] as bool? ?? false,
          dataGroupHashesVerified:
              result['data_group_hashes_verified'] as bool? ?? false,
          countrySigningCertificateVerified:
              result['country_signing_certificate_verified'] as bool? ?? false,
          activeAuthenticationVerified:
              result['active_authentication_verified'] as bool? ?? false,
        ),
      );
    } on PlatformException catch (error) {
      onError(error.message ?? error.code);
    } on Object catch (error) {
      onError(error.toString());
    }
  }

  @override
  Future<void> cancel() async {
    await _channel.invokeMethod<void>('cancel');
  }
}

/// A [NfcPassportReader] that returns a synthetic [PassportData] instantly.
///
/// This implementation is test-only and is never selected by production UI.
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
    required PassportAccessData accessData,
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

  @override
  Future<bool> isAvailable() async => true;
}
