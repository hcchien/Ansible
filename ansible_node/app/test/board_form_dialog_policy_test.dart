import 'dart:convert';

import 'package:ansible_node/widgets/board_form_dialog.dart';
import 'package:ansible_node/services/hosted_issuer_manifest.dart';
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
    expect(find.text('所有人都能閱讀與發文'), findsOneWidget);
    expect(find.byKey(const Key('board_policy_summary')), findsOneWidget);

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

  testWidgets('builds credential policy from hosted issuer manifest', (
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
                    manifestLoader: const _FakeManifestLoader(),
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
    await tester.enterText(find.byType(TextFormField).first, 'Members');
    await tester.ensureVisible(
      find.byKey(const Key('board_audience_mode')),
    );
    await tester.tap(find.byKey(const Key('board_audience_mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他資格才能發文（進階）').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('hosted_issuer_manifest_url')),
      'https://issuer.example/manifest',
    );
    await tester.ensureVisible(find.byKey(const Key('load_issuer_manifest')));
    await tester.tap(find.byKey(const Key('load_issuer_manifest')));
    await tester.pumpAndSettle();
    expect(find.textContaining('party-member-v2'), findsOneWidget);
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();

    final policy =
        jsonDecode(result!['accessPolicyJson']!) as Map<String, dynamic>;
    final requirement =
        policy['requirements']['member'] as Map<String, dynamic>;
    expect(requirement['credential_configuration_id'], 'party-member-v2');
    expect(requirement['credential_type'], 'OrganizationMembershipCredential');
    expect(requirement['trusted_issuers'], ['did:web:party.example']);
    expect(requirement['claims'], [
      {'path': 'membershipActive', 'op': 'equals', 'value': true},
    ]);
  });

  testWidgets(
    'builds public-read Taiwan-citizen-post policy without technical fields',
    (tester) async {
      Map<String, String?>? result;
      final now = DateTime.utc(2026, 7, 24);
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
      await tester.enterText(find.byType(TextFormField).first, 'Taiwan board');
      await tester.ensureVisible(
        find.byKey(const Key('board_audience_mode')),
      );
      await tester.tap(find.byKey(const Key('board_audience_mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('所有人可閱讀，台灣公民才能發文').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hosted_issuer_manifest_url')), findsNothing);
      expect(find.text('可信簽發者 DID'), findsNothing);

      await tester.tap(find.text('儲存'));
      await tester.pumpAndSettle();

      final policy =
          jsonDecode(result!['accessPolicyJson']!) as Map<String, dynamic>;
      expect(policy['discovery'], 'public');
      expect(policy['read'], {'requirement': 'public'});
      expect(policy['post'], {'requirement': 'member'});
      expect(policy['content_visibility'], 'public');
      final requirement =
          policy['requirements']['member'] as Map<String, dynamic>;
      expect(requirement['credential_type'], 'TaiwanCitizenshipCredential');
      expect(requirement['trusted_issuers'], ['did:web:localhost']);
      expect(requirement['claims'], [
        {'path': 'citizenshipVerified', 'op': 'equals', 'value': true},
      ]);
    },
  );
}

class _FakeManifestLoader implements HostedIssuerManifestLoader {
  const _FakeManifestLoader();

  @override
  Future<HostedIssuerManifest> load(Uri manifestUri) async {
    return const HostedIssuerManifest(
      organizationDid: 'did:web:party.example',
      configurations: [
        HostedIssuerCredentialConfiguration(
          id: 'party-member-v2',
          credentialType: 'OrganizationMembershipCredential',
          claims: [
            HostedIssuerClaimConfiguration(
              path: 'membershipActive',
              allowedOperators: {'equals'},
              valueType: 'boolean',
            ),
          ],
        ),
      ],
    );
  }
}
