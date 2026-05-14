import 'package:ansible_node/services/messenger_contact_resolver.dart';
import 'package:ansible_node/services/messenger_relay_client.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'marks contact available when relay reports device with one-time pre-key',
    () async {
      final relay = _FakeMessengerRelayClient(
        response: const MessengerDeviceAvailabilityResponse(
          subjectDid: 'did:plc:alice',
          devices: [
            MessengerDeviceAvailability(
              deviceId: 'msgdev_alice',
              messengerIdentityKey: 'alice_identity',
              signedPreKeyId: 1,
              signedPreKey: 'alice_signed',
              signedPreKeySignature: 'alice_sig',
              hasOneTimePreKeys: true,
            ),
          ],
        ),
      );
      final resolver = MessengerContactResolver(relayClient: relay);

      final availability = await resolver.resolveAvailability(
        ContactRecord(
          subjectDid: 'did:plc:alice',
          createdAt: DateTime.utc(2026, 5, 14),
          updatedAt: DateTime.utc(2026, 5, 14),
        ),
      );

      expect(availability, MessengerAvailability.available);
    },
  );
}

class _FakeMessengerRelayClient extends MessengerRelayClient {
  _FakeMessengerRelayClient({required this.response})
    : super(relayBaseUrl: Uri.parse('http://localhost:4001'));

  final MessengerDeviceAvailabilityResponse response;

  @override
  Future<MessengerDeviceAvailabilityResponse> fetchDeviceAvailability(
    String subjectDid,
  ) async {
    return response;
  }
}
