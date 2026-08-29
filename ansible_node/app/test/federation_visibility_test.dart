import 'package:ansible_node/widgets/content_visibility_sheet.dart';
import 'package:ansible_node/services/fediverse_preferences_controller.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('private visibility disables federation targets', (tester) async {
    ContentDistributionChoice? choice;
    await _pumpDistributionSheet(
      tester,
      current: const ContentDistributionChoice(
        visibility: ContentVisibility.private,
        distributionPreference: DistributionPreference.localOnly,
      ),
      onResult: (value) => choice = value,
    );

    expect(find.text('local only'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.descendant(
              of: find.byKey(const Key('distribution_nostr_toggle')),
              matching: find.byType(SwitchListTile),
            ),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.descendant(
              of: find.byKey(const Key('distribution_activitypub_toggle')),
              matching: find.byType(SwitchListTile),
            ),
          )
          .onChanged,
      isNull,
    );

    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    expect(choice!.visibility, ContentVisibility.private);
    expect(choice!.distributionPreference, DistributionPreference.localOnly);
  });

  testWidgets('public visibility can choose Nostr only', (tester) async {
    ContentDistributionChoice? choice;
    await _pumpDistributionSheet(
      tester,
      current: ContentDistributionChoice.forVisibility(
        ContentVisibility.public,
      ),
      onResult: (value) => choice = value,
    );

    expect(find.text('local only'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('distribution_nostr_toggle')),
    );
    await tester.tap(find.byKey(const Key('distribution_nostr_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Nostr'), findsWidgets);

    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    expect(choice!.visibility, ContentVisibility.public);
    expect(choice!.distributionPreference, DistributionPreference.nostr);
  });

  testWidgets('approved followers is host-visible and never federated', (
    tester,
  ) async {
    ContentDistributionChoice? choice;
    await _pumpDistributionSheet(
      tester,
      current: ContentDistributionChoice.forVisibility(
        ContentVisibility.followers,
      ),
      onResult: (value) => choice = value,
    );

    expect(find.textContaining('託管 Host 可讀取內容'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.descendant(
              of: find.byKey(const Key('distribution_nostr_toggle')),
              matching: find.byType(SwitchListTile),
            ),
          )
          .onChanged,
      isNull,
    );
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(choice!.visibility, ContentVisibility.followers);
    expect(choice!.distributionPreference, DistributionPreference.localOnly);
  });

  testWidgets('unverified user cannot select ActivityPub distribution', (
    tester,
  ) async {
    ContentDistributionChoice? choice;
    await _pumpDistributionSheet(
      tester,
      current: ContentDistributionChoice.forVisibility(
        ContentVisibility.unlisted,
      ),
      onResult: (value) => choice = value,
    );

    final activityPubToggle = tester.widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(const Key('distribution_activitypub_toggle')),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(activityPubToggle.onChanged, isNull);
    expect(find.text('需先在設定完成真人驗證並啟用 Fediverse 發布。'), findsOneWidget);

    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    expect(choice!.visibility, ContentVisibility.unlisted);
    expect(choice!.distributionPreference, DistributionPreference.localOnly);
  });

  testWidgets('explicit Fediverse consent permits ActivityPub selection', (
    tester,
  ) async {
    ContentDistributionChoice? choice;
    await _pumpDistributionSheet(
      tester,
      current: ContentDistributionChoice.forVisibility(
        ContentVisibility.public,
      ),
      authorDid: 'did:elix:verified',
      preferencesStore: _EnabledFediverseStore(),
      onResult: (value) => choice = value,
    );

    await tester.ensureVisible(
      find.byKey(const Key('distribution_activitypub_toggle')),
    );
    await tester.tap(find.byKey(const Key('distribution_activitypub_toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    expect(choice!.distributionPreference, DistributionPreference.activityPub);
  });

  testWidgets('unlisted visibility copy does not mention demo circle names', (
    tester,
  ) async {
    await _pumpDistributionSheet(
      tester,
      current: ContentDistributionChoice.forVisibility(
        ContentVisibility.unlisted,
      ),
      onResult: (_) {},
    );

    expect(find.text('不列出'), findsOneWidget);
    expect(find.textContaining('讀書會'), findsNothing);
  });
}

Future<void> _pumpDistributionSheet(
  WidgetTester tester, {
  required ContentDistributionChoice current,
  required ValueChanged<ContentDistributionChoice?> onResult,
  String? authorDid,
  FediversePreferencesStore? preferencesStore,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onResult(
                    await showContentDistributionSheet(
                      context: context,
                      current: current,
                      subjectLabel: '這則內容',
                      authorDid: authorDid,
                      preferencesStore:
                          preferencesStore ??
                          const SharedPreferencesFediversePreferencesStore(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _EnabledFediverseStore implements FediversePreferencesStore {
  @override
  Future<FediversePreferences> load(String did) async =>
      const FediversePreferences(enabled: true);

  @override
  Future<void> save(String did, FediversePreferences preferences) async {}
}
