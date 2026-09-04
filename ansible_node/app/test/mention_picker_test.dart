import 'package:ansible_node/screens/post_composer_screen.dart';
import 'package:ansible_node/services/discovery_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reply picker inserts a handle and returns its resolved DID', (
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
    await tester.tap(find.byKey(const Key('post_composer_mention_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mention_search_field')),
      'ali',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mention_actor_did:plc:alice')));
    await tester.pumpAndSettle();

    expect(find.textContaining('@alice.elix.cool'), findsOneWidget);
    await tester.tap(find.byKey(const Key('post_composer_done_button')));
    await tester.pumpAndSettle();

    expect(find.text('did:plc:alice'), findsOneWidget);
    expect(find.text('@alice.elix.cool'), findsOneWidget);
  });

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
    expect(field.controller!.text, 'Hello @alice.elix.cool ');
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
