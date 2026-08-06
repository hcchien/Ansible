import 'package:ansible_node/services/relay_handle_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('keeps a separate handle for each Relay space', () async {
    const store = SecureRelayHandleStore();
    await store.save('https://relay.elix.cool', 'hcchien.elix.cool');
    await store.save('https://relay.new-elix.cool', 'hcchien2.new-elix.cool');

    expect(await store.load('https://relay.elix.cool'), 'hcchien.elix.cool');
    expect(
      await store.load('https://relay.new-elix.cool'),
      'hcchien2.new-elix.cool',
    );
  });

  test('normalizes a Relay URL to one handle binding', () async {
    const store = SecureRelayHandleStore();
    await store.save('https://RELAY.elix.cool/', 'hcchien.elix.cool');

    expect(await store.load('https://relay.elix.cool'), 'hcchien.elix.cool');
  });
}
