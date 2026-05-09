import 'package:ansible_node/services/nostr_relay_settings_store.dart';
import 'package:ansible_node/widgets/nostr_relay_settings_panel.dart';
import 'package:ansible_nostr/ansible_nostr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageNostrRelaySettingsStore', () {
    const storage = FlutterSecureStorage();

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('persists read and write relay preferences', () async {
      final store = SecureStorageNostrRelaySettingsStore(
        secureStorage: storage,
      );

      await store.save([
        const NostrRelayPreference(url: 'wss://read.example', read: true),
        const NostrRelayPreference(url: 'wss://write.example', write: true),
        const NostrRelayPreference(
          url: 'wss://both.example',
          read: true,
          write: true,
        ),
      ]);

      final relays = await store.list();

      expect(relays, hasLength(3));
      expect(relays[0].url, 'wss://read.example');
      expect(relays[0].read, isTrue);
      expect(relays[0].write, isFalse);
      expect(relays[1].read, isFalse);
      expect(relays[1].write, isTrue);
      expect(relays[2].read, isTrue);
      expect(relays[2].write, isTrue);
    });

    test('normalizes duplicate relay urls when saving', () async {
      final store = SecureStorageNostrRelaySettingsStore(
        secureStorage: storage,
      );

      await store.save([
        const NostrRelayPreference(url: ' wss://relay.example ', read: true),
        const NostrRelayPreference(url: 'wss://relay.example', write: true),
      ]);

      final relays = await store.list();

      expect(relays, hasLength(1));
      expect(relays.single.url, 'wss://relay.example');
      expect(relays.single.read, isTrue);
      expect(relays.single.write, isTrue);
    });
  });

  group('NostrRelaySettingsPanel', () {
    testWidgets('adds, toggles, and removes relay preferences', (tester) async {
      var relays = <NostrRelayPreference>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return NostrRelaySettingsPanel(
                  relays: relays,
                  onChanged: (next) => setState(() => relays = next),
                );
              },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('nostr_relay_url_field')),
        'wss://relay.example',
      );
      await tester.tap(find.byKey(const Key('nostr_add_relay_button')));
      await tester.pumpAndSettle();

      expect(relays, hasLength(1));
      expect(relays.single.url, 'wss://relay.example');
      expect(relays.single.read, isTrue);
      expect(relays.single.write, isTrue);

      await tester.tap(find.byKey(const Key('nostr_relay_write_0')));
      await tester.pumpAndSettle();

      expect(relays.single.read, isTrue);
      expect(relays.single.write, isFalse);

      await tester.tap(find.byKey(const Key('nostr_remove_relay_0')));
      await tester.pumpAndSettle();

      expect(relays, isEmpty);
    });
  });
}
