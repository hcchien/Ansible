import 'package:ansible_store/ansible_store.dart';

import 'messenger_relay_client.dart';

class MessengerContactResolver {
  MessengerContactResolver({required this.relayClient});

  final MessengerRelayClient relayClient;

  Future<MessengerAvailability> resolveAvailability(
    ContactRecord contact,
  ) async {
    if (contact.relationship == ContactRelationship.blocked ||
        contact.trustState == ContactTrustState.blocked) {
      return MessengerAvailability.blocked;
    }
    if (contact.trustState == ContactTrustState.changed) {
      return MessengerAvailability.unresolved;
    }

    try {
      final response = await relayClient.fetchDeviceAvailability(
        contact.subjectDid,
      );
      if (response.devices.isEmpty) return MessengerAvailability.noDevices;
      if (response.devices.any((device) => device.hasOneTimePreKeys)) {
        return MessengerAvailability.available;
      }
      return MessengerAvailability.noPreKeys;
    } catch (_) {
      return MessengerAvailability.relayUnavailable;
    }
  }
}
