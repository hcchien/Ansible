import 'package:ansible_node/widgets/content_visibility_sheet.dart';
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

    expect(find.text('Nostr + ActivityPub'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('distribution_activitypub_toggle')),
    );
    await tester.tap(find.byKey(const Key('distribution_activitypub_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Nostr'), findsWidgets);

    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    expect(choice!.visibility, ContentVisibility.public);
    expect(choice!.distributionPreference, DistributionPreference.nostr);
  });

  testWidgets('unlisted visibility can choose ActivityPub only', (
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

    await tester.ensureVisible(
      find.byKey(const Key('distribution_nostr_toggle')),
    );
    await tester.tap(find.byKey(const Key('distribution_nostr_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('ActivityPub'), findsWidgets);

    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();

    expect(choice!.visibility, ContentVisibility.unlisted);
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
