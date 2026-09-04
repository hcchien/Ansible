import 'package:ansible_node/screens/post_composer_screen.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:ansible_node/theme/ansible_design.dart';
import 'package:ansible_node/widgets/mention_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mention token prefers display name while keeping duplicate labels safe',
    () {
      final draft = MentionDraft();
      const first = DiscoveredActor(
        did: 'did:plc:alice-one',
        handle: 'alice.one',
        displayName: 'Alice',
      );
      const second = DiscoveredActor(
        did: 'did:plc:alice-two',
        handle: 'alice.two',
        displayName: 'Alice',
      );

      expect(draft.record(first), '@Alice');
      expect(draft.record(second), '@Alice (@alice.two)');
      expect(draft.activeDids('@Alice and @Alice (@alice.two)'), [
        'did:plc:alice-one',
        'did:plc:alice-two',
      ]);
    },
  );

  testWidgets(
    'reply picker inserts a display name and returns its resolved DID',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: _ComposerHarness(
            search: (query) async {
              expect(query, 'ali');
              return const [
                DiscoveredActor(
                  did: 'did:plc:alice',
                  handle: 'alice.elix.cool',
                  displayName: 'Alice',
                ),
              ];
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_composer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('post_composer_mention_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mention_search_field')),
        'ali',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const Key('mention_search_field')),
      );
      expect(field.style?.color, AnsibleDesign.ink);
      expect(field.decoration?.fillColor, AnsibleDesign.paperElev);
      expect(
        tester.widget<Text>(find.text('Alice')).style?.color,
        AnsibleDesign.ink,
      );
      expect(
        tester.widget<Text>(find.text('@alice.elix.cool')).style?.color,
        AnsibleDesign.inkMuted,
      );

      await tester.tap(find.byKey(const Key('mention_actor_did:plc:alice')));
      await tester.pumpAndSettle();

      expect(find.textContaining('@Alice'), findsOneWidget);
      await tester.tap(find.byKey(const Key('post_composer_done_button')));
      await tester.pumpAndSettle();

      expect(find.text('did:plc:alice'), findsOneWidget);
      expect(find.text('@Alice'), findsOneWidget);
    },
  );

  testWidgets('typing @ opens the reply picker and replaces the trigger', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _ComposerHarness(
          search: (query) async {
            expect(query, 'ali');
            return const [
              DiscoveredActor(
                did: 'did:plc:alice',
                handle: 'alice.elix.cool',
                displayName: 'Alice',
              ),
            ];
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_composer')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('post_composer_body_field')),
      'Hello @',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mention_search_field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('mention_search_field')),
      'ali',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mention_actor_did:plc:alice')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('post_composer_body_field')),
    );
    expect(field.controller!.text, 'Hello @Alice ');
    await tester.tap(find.byKey(const Key('post_composer_done_button')));
    await tester.pumpAndSettle();
    expect(find.text('did:plc:alice'), findsOneWidget);
  });
}

class _ComposerHarness extends StatefulWidget {
  const _ComposerHarness({required this.search});

  final Future<List<DiscoveredActor>> Function(String query) search;

  @override
  State<_ComposerHarness> createState() => _ComposerHarnessState();
}

class _ComposerHarnessState extends State<_ComposerHarness> {
  PostComposerResult? _result;

  Future<void> _open() async {
    final result = await Navigator.of(context).push<PostComposerResult>(
      MaterialPageRoute(
        builder: (_) => PostComposerScreen(
          authorDid: 'did:plc:local',
          mentionSearch: widget.search,
        ),
      ),
    );
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            key: const Key('open_composer'),
            onPressed: _open,
            child: const Text('open'),
          ),
          if (_result != null) ...[
            Text(_result!.content),
            Text(_result!.mentionDids.join(',')),
          ],
        ],
      ),
    );
  }
}
