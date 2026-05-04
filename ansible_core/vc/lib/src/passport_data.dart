import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Raw data extracted from an ePassport NFC chip (ICAO 9303).
///
/// Read via:
///   iOS    → CoreNFC  (NFCTagReaderSession, ISO 7816-4 APDU)
///   Android → Android NFC (IsoDep / APDU)
///
/// Only the fields required for ZKP input and DID anchoring are kept here.
/// The raw DG and SOD byte arrays are preserved so the Rust FFI layer can
/// perform its own parsing and signature verification.
class PassportData {
  // ── MRZ fields (parsed from DG1) ──────────────────────────────────────────

  /// Passport document number — 9 characters (TD3 format).
  final String documentNumber;

  /// Date of birth in YYMMDD format.
  final String dateOfBirth;

  /// Date of expiry in YYMMDD format.
  final String dateOfExpiry;

  /// ISO 3166-1 alpha-3 nationality code.
  final String nationality;

  // ── Raw NFC byte arrays ───────────────────────────────────────────────────

  /// DG1 — Personal data file (includes MRZ, 88 bytes payload for TD3).
  final List<int> dg1Bytes;

  /// DG2 — Encoded face photo (JPEG2000 / JPEG). Optional; may be null if
  /// the reader chose to skip it (e.g. to speed up the session).
  final List<int>? dg2Bytes;

  /// SOD — Document Security Object (chip signature over DG hashes; used as
  /// ZKP private input for passport signature verification).
  final List<int> sodBytes;

  // ── Computed fields ────────────────────────────────────────────────────────

  /// Hex-encoded SHA-256 of (documentNumber || dateOfBirth || dateOfExpiry).
  ///
  /// This is the ZKP private input "passport_secret". It is deterministic for
  /// a given passport so the nullifier is also deterministic, while never
  /// revealing which passport was scanned.
  final String passportSecret;

  const PassportData({
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
    required this.nationality,
    required this.dg1Bytes,
    this.dg2Bytes,
    required this.sodBytes,
    required this.passportSecret,
  });

  /// Parse a TD3 (passport) MRZ and return a [PassportData] with raw byte
  /// arrays initialised to empty lists.  Useful for testing and for cases
  /// where only the MRZ strings are available (e.g. optical scan fallback).
  ///
  /// TD3 MRZ layout (ICAO 9303-4):
  ///   Line 1 (44 chars): P<NATIONALITY<SURNAME<<GIVEN<NAMES...
  ///   Line 2 (44 chars): DOCNUMBER<CHECKDIGIT NATIONALITY DOBCDDOECD ...
  ///     positions 0-8  : document number (9 chars)
  ///     position  9    : check digit
  ///     positions 10-15: nationality (3) + date of birth (6) — DOB at [13-18]
  ///
  /// ICAO 9303-5 §4.2.1 Line 2 detailed layout:
  ///   [0-8]   document number
  ///   [9]     check digit (doc number)
  ///   [10-12] nationality
  ///   [13-18] date of birth  (YYMMDD)
  ///   [19]    check digit (DOB)
  ///   [20]    sex
  ///   [21-26] date of expiry (YYMMDD)
  ///   [27]    check digit (DOE)
  factory PassportData.fromMrz(String mrzLine1, String mrzLine2) {
    if (mrzLine1.length != 44) {
      throw ArgumentError(
        'MRZ line 1 must be 44 characters, got ${mrzLine1.length}',
      );
    }
    if (mrzLine2.length != 44) {
      throw ArgumentError(
        'MRZ line 2 must be 44 characters, got ${mrzLine2.length}',
      );
    }

    final documentNumber = mrzLine2.substring(0, 9);
    final nationality    = mrzLine2.substring(10, 13);
    final dateOfBirth    = mrzLine2.substring(13, 19);
    final dateOfExpiry   = mrzLine2.substring(21, 27);
    final secret         = _computePassportSecret(documentNumber, dateOfBirth, dateOfExpiry);

    return PassportData(
      documentNumber: documentNumber,
      dateOfBirth:    dateOfBirth,
      dateOfExpiry:   dateOfExpiry,
      nationality:    nationality,
      dg1Bytes:       [],
      sodBytes:       [],
      passportSecret: secret,
    );
  }

  /// Whether the passport has passed its date of expiry.
  ///
  /// Interprets YYMMDD as 20YY (valid for years 2000-2099).
  bool get isExpired {
    try {
      final yy = int.parse(dateOfExpiry.substring(0, 2));
      final mm = int.parse(dateOfExpiry.substring(2, 4));
      final dd = int.parse(dateOfExpiry.substring(4, 6));
      final expiry = DateTime(2000 + yy, mm, dd);
      return DateTime.now().isAfter(expiry);
    } catch (_) {
      // If parsing fails treat as expired to be safe.
      return true;
    }
  }

  /// Compute hex(SHA-256(documentNumber || dateOfBirth || dateOfExpiry)).
  static String _computePassportSecret(
    String documentNumber,
    String dateOfBirth,
    String dateOfExpiry,
  ) {
    final input = utf8.encode(documentNumber + dateOfBirth + dateOfExpiry);
    final digest = sha256.convert(input);
    return digest.toString(); // hex string
  }
}
