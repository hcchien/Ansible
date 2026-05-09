import 'package:ansible_node/widgets/nostr_publication_retry_panel.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows failed targets and exposes retry/reset actions', (
    tester,
  ) async {
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NostrPublicationRetryPanel(
            failedTargets: [
              PublicationTarget(
                targetId: 'target-1',
                intentId: 'intent-1',
                protocol: PublicationProtocol.nostr,
                endpoint: 'wss://relay.example',
                status: PublicationStatus.failed,
                error: 'relay down',
              ),
            ],
            onRetry: (target) async => actions.add('retry:${target.targetId}'),
            onReset: (target) async => actions.add('reset:${target.targetId}'),
          ),
        ),
      ),
    );

    expect(find.text('wss://relay.example'), findsOneWidget);
    expect(find.textContaining('relay down'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retry-target-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reset-target-1')));
    await tester.pump();

    expect(actions, ['retry:target-1', 'reset:target-1']);
  });

  testWidgets('hides itself when there are no failed targets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NostrPublicationRetryPanel(
            failedTargets: const [],
            onRetry: (_) async {},
            onReset: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byType(NostrPublicationRetryPanel), findsOneWidget);
    expect(find.text('Nostr 發佈待處理'), findsNothing);
  });
}
