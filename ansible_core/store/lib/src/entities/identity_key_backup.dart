import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Passphrase-encrypted backup of the identity (content) key — design D5-b.
///
/// Constitution Review item 2: the identity key leaves the device ONLY as this
/// passphrase-encrypted ciphertext, chosen explicitly by the user (opt-in).
/// The relay (or any holder) sees ciphertext only and cannot decrypt it.
///
/// Crypto chosen for the FOUNDATION slice (Dart-only, pure-Dart `cryptography`
/// package — no native deps so `dart test` works):
///   - KDF:  PBKDF2-HMAC-SHA256 (RFC 2898), [pbkdf2Iterations] iterations.
///   - AEAD: AES-256-GCM.
///
/// TODO(Task 1/2, rust/core): the design specifies NIP-49-style scrypt +
/// XChaCha20-Poly1305. PBKDF2 + AES-GCM is the explicitly-allowed interim
/// (see plan: "scrypt or PBKDF2 KDF + an AEAD like AES-GCM/XChaCha20 is fine").
/// Move to scrypt/XChaCha20 in `ansible_rust_core` and bump [formatVersion]
/// (the [kdf]/[cipher] fields in the blob make that a clean, detectable
/// migration). `cryptography` does not ship scrypt; rust does.
class IdentityKeyBackup {
  /// Versioned, self-describing envelope identifier.
  static const String typeName = 'io.trisaura.identity.key_backup';
  static const int formatVersion = 1;

  static const String kdfPbkdf2 = 'pbkdf2-hmac-sha256';
  static const String cipherAesGcm = 'aes-256-gcm';

  /// PBKDF2 iteration count. Conservative for a pure-Dart KDF; raise (or move
  /// to scrypt in rust) before relay-stored ciphertext ships at scale.
  static const int pbkdf2Iterations = 210000;

  static const int _saltLengthBytes = 16;
  static const int _keyLengthBytes = 32; // AES-256

  const IdentityKeyBackup._();

  /// Encrypts [identityPrivateKeyHex] (the raw Ed25519 private key, hex) with a
  /// key derived from [passphrase] and returns a self-describing JSON blob
  /// (the only form the key leaves the device in).
  ///
  /// [did] and [handle] are stored in the blob (cleartext) purely so a restore
  /// UI / the recovery flow can tell which account a blob belongs to WITHOUT
  /// the passphrase — they are NOT secret. This is what makes the backup
  /// self-describing: blob + passphrase is enough to recover, no separate note
  /// of "which account". No raw legal identity is ever included (Constitution
  /// item 4): did + handle are public identifiers, never legal identity.
  static Future<String> encrypt({
    required String passphrase,
    required String identityPrivateKeyHex,
    String? did,
    String? handle,
  }) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    final salt = _randomBytes(_saltLengthBytes);
    final secretKey = await _deriveKey(passphrase, salt);

    final aead = AesGcm.with256bits();
    final secretBox = await aead.encrypt(
      utf8.encode(identityPrivateKeyHex),
      secretKey: secretKey,
    );

    final blob = <String, Object?>{
      'type': typeName,
      'format_version': formatVersion,
      'kdf': kdfPbkdf2,
      'kdf_iterations': pbkdf2Iterations,
      'cipher': cipherAesGcm,
      if (did != null) 'did': did,
      if (handle != null) 'handle': handle,
      'salt': base64.encode(salt),
      'nonce': base64.encode(secretBox.nonce),
      'ciphertext': base64.encode(secretBox.cipherText),
      'mac': base64.encode(secretBox.mac.bytes),
    };
    return jsonEncode(blob);
  }

  /// Decrypts a blob produced by [encrypt] back to the identity private key
  /// hex. Throws [BackupDecryptException] on a wrong passphrase or tampered
  /// blob (the AEAD MAC fails cleanly), and [BackupFormatException] on an
  /// unparseable / unsupported blob.
  static Future<String> decrypt({
    required String passphrase,
    required String blobJson,
  }) async {
    final parsed = parse(blobJson);

    final secretKey = await _deriveKey(passphrase, parsed.salt);
    final secretBox = SecretBox(
      parsed.ciphertext,
      nonce: parsed.nonce,
      mac: Mac(parsed.mac),
    );

    try {
      final clear = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: secretKey,
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      // Wrong passphrase OR tampered ciphertext: the GCM tag check failed.
      throw const BackupDecryptException(
        'Wrong passphrase or corrupted backup.',
      );
    }
  }

  /// Parses and validates the structure of a backup blob without attempting to
  /// decrypt it. Useful for restore UIs ("this is a valid Ansible backup for
  /// did:plc:…") and exercised by tests.
  static ParsedKeyBackup parse(String blobJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(blobJson);
    } on FormatException catch (e) {
      throw BackupFormatException('Not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const BackupFormatException('Backup is not a JSON object.');
    }
    final map = decoded;
    if (map['type'] != typeName) {
      throw BackupFormatException(
        'Unexpected type: ${map['type']}',
      );
    }
    final version = (map['format_version'] as num?)?.toInt();
    if (version == null || version > formatVersion) {
      throw BackupFormatException('Unsupported format_version: $version');
    }
    if (map['kdf'] != kdfPbkdf2) {
      throw BackupFormatException('Unsupported kdf: ${map['kdf']}');
    }
    if (map['cipher'] != cipherAesGcm) {
      throw BackupFormatException('Unsupported cipher: ${map['cipher']}');
    }
    Uint8List field(String key) {
      final value = map[key];
      if (value is! String) {
        throw BackupFormatException('Missing field: $key');
      }
      try {
        return base64.decode(value);
      } on FormatException {
        throw BackupFormatException('Field $key is not valid base64.');
      }
    }

    return ParsedKeyBackup(
      formatVersion: version,
      kdfIterations:
          (map['kdf_iterations'] as num?)?.toInt() ?? pbkdf2Iterations,
      did: map['did'] as String?,
      handle: map['handle'] as String?,
      salt: field('salt'),
      nonce: field('nonce'),
      ciphertext: field('ciphertext'),
      mac: field('mac'),
    );
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pbkdf2Iterations,
      bits: _keyLengthBytes * 8,
    );
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Uint8List _randomBytes(int length) {
    final secretKey = SecretKeyData.random(length: length);
    return Uint8List.fromList(secretKey.bytes);
  }
}

/// Structural view of a parsed (but not decrypted) backup blob.
class ParsedKeyBackup {
  final int formatVersion;
  final int kdfIterations;
  final String? did;
  final String? handle;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List mac;

  const ParsedKeyBackup({
    required this.formatVersion,
    required this.kdfIterations,
    required this.did,
    required this.handle,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });
}

/// Thrown when decryption fails (wrong passphrase or tampered ciphertext).
class BackupDecryptException implements Exception {
  final String message;
  const BackupDecryptException(this.message);
  @override
  String toString() => 'BackupDecryptException: $message';
}

/// Thrown when a blob cannot be parsed or its format is unsupported.
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => 'BackupFormatException: $message';
}
