import 'package:ansible_node/services/credential_payload_codec.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'stores wallet payload outside SQLite and decodes by secure reference',
    () async {
      final codec = SecureCredentialPayloadCodec(
        secureStorage: const FlutterSecureStorage(),
      );

      final envelope = await codec.seal(
        credentialId: 'vc-1',
        payloadJson: '{"id":"vc-1","claim":"verified"}',
      );

      expect(envelope.encryptionVersion, SecureCredentialPayloadCodec.version);
      expect(envelope.encodedPayload, 'secure-storage-json-v1:vc-1');
      expect(envelope.encodedPayload, isNot(contains('verified')));

      final decoded = await codec.decode(envelope.encodedPayload);
      expect(decoded['id'], 'vc-1');
      expect(decoded['claim'], 'verified');
    },
  );

  test(
    'continues to decode legacy plain-json payloads for migration',
    () async {
      final codec = SecureCredentialPayloadCodec(
        secureStorage: const FlutterSecureStorage(),
      );

      final decoded = await codec.decode('{"id":"legacy-vc"}');

      expect(decoded['id'], 'legacy-vc');
    },
  );
}
