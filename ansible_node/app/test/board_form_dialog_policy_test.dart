import 'dart:convert';

import 'package:ansible_node/widgets/board_form_dialog.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new hosted board defaults to an explicit public policy', (
    tester,
  ) async {
    Map<String, String?>? result;
    final now = DateTime.utc(2026, 7, 22);
    final host = RemoteNode(
      id: 'relay-dev',
      name: 'Elix Relay',
      url: 'https://relay-dev.elix.cool',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<Map<String, String?>>(
                  context: context,
                  builder: (_) => BoardFormDialog(
                    forumHosts: [host],
                    requireForumHost: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('公開看板'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Public board');
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!['contentVisibility'], 'public');
    expect(jsonDecode(result!['federationPolicyJson']!)['mode'], 'enabled');
    final policy =
        jsonDecode(result!['accessPolicyJson']!) as Map<String, dynamic>;
    expect(policy['discovery'], 'public');
    expect(policy['read'], {'requirement': 'public'});
    expect(policy['content_visibility'], 'public');
    expect(policy['federation'], 'enabled');
  });
}
