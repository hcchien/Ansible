import 'dart:convert';

import 'package:ansible_store/ansible_store.dart';
import 'package:test/test.dart';

void main() {
  // A representative raw Ed25519 private key (hex, 64 bytes). Not a real key.
  const keyHex =
      '9d61b19deff3a5b0ba849d0064cb8a4128b6a0c0d3c1b2e7f8a9b0c1d2e3f40'
      '5162738495a6b7c8d9e0f1a2b3c4d5e6f70819202122232425262728292a2b';

  group('IdentityKeyBackup', () {
    test('encrypt then decrypt round-trips the key', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'correct horse battery staple',
        identityPrivateKeyHex: keyHex,
        did: 'did:plc:alice',
      );
      final restored = await IdentityKeyBackup.decrypt(
        passphrase: 'correct horse battery staple',
        blobJson: blob,
      );
      expect(restored, keyHex);
    });

    test('round-trips did + handle alongside the key', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'correct horse battery staple',
        identityPrivateKeyHex: keyHex,
        did: 'did:plc:alice',
        handle: 'alice.elix.cool',
      );
      // did + handle readable from the blob WITHOUT the key being exposed.
      final parsed = IdentityKeyBackup.parse(blob);
      expect(parsed.did, 'did:plc:alice');
      expect(parsed.handle, 'alice.elix.cool');
      expect(blob.contains(keyHex), isFalse);

      // The key itself only comes back with the passphrase.
      final restored = await IdentityKeyBackup.decrypt(
        passphrase: 'correct horse battery staple',
        blobJson: blob,
      );
      expect(restored, keyHex);
    });

    test('handle is cleartext metadata, not part of the ciphertext', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'pw',
        identityPrivateKeyHex: keyHex,
        did: 'did:plc:alice',
        handle: 'alice.elix.cool',
      );
      final map = jsonDecode(blob) as Map<String, Object?>;
      expect(map['did'], 'did:plc:alice');
      expect(map['handle'], 'alice.elix.cool');
    });

    test('wrong passphrase fails cleanly', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'right-passphrase',
        identityPrivateKeyHex: keyHex,
      );
      expect(
        () => IdentityKeyBackup.decrypt(
          passphrase: 'wrong-passphrase',
          blobJson: blob,
        ),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('the key never appears in plaintext inside the blob', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'pw',
        identityPrivateKeyHex: keyHex,
        did: 'did:plc:alice',
      );
      expect(blob.contains(keyHex), isFalse);
      // did is allowed in cleartext (not secret); raw key is not.
      expect(blob.contains('did:plc:alice'), isTrue);
    });

    test('blob format parses with the expected envelope', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'pw',
        identityPrivateKeyHex: keyHex,
        did: 'did:plc:alice',
      );
      final map = jsonDecode(blob) as Map<String, Object?>;
      expect(map['type'], IdentityKeyBackup.typeName);
      expect(map['format_version'], IdentityKeyBackup.formatVersion);
      expect(map['kdf'], IdentityKeyBackup.kdfPbkdf2);
      expect(map['cipher'], IdentityKeyBackup.cipherAesGcm);

      final parsed = IdentityKeyBackup.parse(blob);
      expect(parsed.did, 'did:plc:alice');
      expect(parsed.salt, isNotEmpty);
      expect(parsed.nonce, isNotEmpty);
      expect(parsed.ciphertext, isNotEmpty);
      expect(parsed.mac, isNotEmpty);
    });

    test('parse rejects a non-backup blob', () {
      expect(
        () => IdentityKeyBackup.parse('{"type":"something.else"}'),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => IdentityKeyBackup.parse('not json'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('tampered ciphertext is rejected by the AEAD', () async {
      final blob = await IdentityKeyBackup.encrypt(
        passphrase: 'pw',
        identityPrivateKeyHex: keyHex,
      );
      final map = jsonDecode(blob) as Map<String, Object?>;
      // Flip the ciphertext.
      map['ciphertext'] = base64.encode(
        List<int>.filled(base64.decode(map['ciphertext']! as String).length, 0),
      );
      expect(
        () => IdentityKeyBackup.decrypt(
          passphrase: 'pw',
          blobJson: jsonEncode(map),
        ),
        throwsA(isA<BackupDecryptException>()),
      );
    });

    test('empty passphrase is rejected', () {
      expect(
        () => IdentityKeyBackup.encrypt(
          passphrase: '',
          identityPrivateKeyHex: keyHex,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
