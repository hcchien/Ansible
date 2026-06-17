import 'dart:convert';

import 'package:ansible_node/l10n/app_localizations.dart';
import 'package:ansible_node/screens/credential_admin_screen.dart';
import 'package:ansible_node/screens/credential_issuance_wizard.dart';
import 'package:ansible_node/screens/home_shell.dart';
import 'package:ansible_node/screens/inbox_screen.dart';
import 'package:ansible_node/screens/murmur_detail_screen.dart';
import 'package:ansible_node/screens/murmur_screen.dart';
import 'package:ansible_node/screens/note_detail_screen.dart';
import 'package:ansible_node/screens/note_editor_screen.dart';
import 'package:ansible_node/screens/note_workspace_screen.dart';
import 'package:ansible_node/screens/passkeys_registration_screen.dart';
import 'package:ansible_node/screens/profile_screen.dart';
import 'package:ansible_node/screens/search_screen.dart';
import 'package:ansible_node/screens/wallet_screen.dart';
import 'package:ansible_node/screens/wallet_verifier_consent_screen.dart';
import 'package:ansible_node/services/atproto_client.dart';
import 'package:ansible_node/services/oid4vp_presentation_service.dart';
import 'package:ansible_node/services/oid4vp_request.dart';
import 'package:ansible_node/widgets/ai_provider_setup_sheet.dart';
import 'package:ansible_node/widgets/content_visibility_sheet.dart';
import 'package:ansible_node/widgets/feed_filter_tabs.dart';
import 'package:ansible_node/widgets/summary_review_sheet.dart';
import 'package:ansible_node/screens/thread_composer_screen.dart';
import 'package:ansible_node/widgets/transformation_review_sheet.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('primary non-settings screens use selected English locale', (
    tester,
  ) async {
    await _pumpLocalized(
      tester,
      const Column(
        children: [
          Expanded(child: SearchScreen()),
          SizedBox(height: 240, child: MurmurScreen(authorDid: 'did:test:me')),
          FeedFilterTabs(selected: FeedFilter.all, onChanged: _ignoreFilter),
        ],
      ),
      locale: const Locale('en'),
    );

    expect(find.text('Feed'), findsWidgets);
    expect(find.text('My'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Boards'), findsOneWidget);
    expect(find.textContaining('Search murmurs'), findsOneWidget);

    expect(find.text('全部'), findsNothing);
    expect(find.text('送出'), findsNothing);
    expect(find.text('本地'), findsNothing);
  });

  testWidgets('notes workspace uses selected English locale', (tester) async {
    await _pumpLocalized(
      tester,
      const NoteWorkspaceScreen(authorDid: 'did:test:me'),
      locale: const Locale('en'),
    );

    expect(find.text('Working Notes'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('New Note'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('No loose murmurs yet.'), findsOneWidget);
    expect(find.text('Lineage'), findsOneWidget);

    expect(find.text('草地'), findsNothing);
    expect(find.text('新增筆記'), findsNothing);
    expect(find.text('還沒有筆記'), findsNothing);
  });

  testWidgets('discussion composer uses selected English locale', (
    tester,
  ) async {
    final board = Board(
      id: 'board-1',
      slug: 'general',
      title: 'General',
      description: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    await _pumpLocalized(
      tester,
      ThreadComposerScreen(boards: [board]),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEW DISCUSSION'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);

    // No Chinese leakage under the English locale.
    expect(find.text('取消'), findsNothing);
    expect(find.text('建立'), findsNothing);
    expect(find.textContaining('新討論'), findsNothing);
  });

  testWidgets('settings subpages use selected English locale', (tester) async {
    await _pumpLocalizedScreen(
      tester,
      const InboxScreen(),
      locale: const Locale('en'),
    );
    expect(find.text('No inbox items'), findsOneWidget);
    expect(find.text('目前沒有收信'), findsNothing);

    await _pumpLocalizedScreen(
      tester,
      WalletScreen(
        holderDid: 'did:plc:abcdefghijklmnop',
        repository: InMemoryWalletRepository(),
      ),
      locale: const Locale('en'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('No credentials yet'), findsOneWidget);
    expect(find.text('錢包'), findsNothing);

    await _pumpLocalizedScreen(
      tester,
      const CredentialAdminScreen(),
      locale: const Locale('en'),
    );
    expect(find.text('No grant records yet'), findsOneWidget);
    expect(find.text('目前沒有授權紀錄'), findsNothing);
  });

  testWidgets('home shell and settings do not expose Chinese UI in English', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'elix_board_swipe_shown': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await _pumpLocalizedScreen(
      tester,
      HomeShell(db: db, did: 'did:plc:abcdefghijklmnop'),
      locale: const Locale('en'),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_cjkUiStrings(tester), isEmpty);

    await tester.tap(find.byKey(const Key('settings_button')));
    await tester.pumpAndSettle();

    expect(_cjkUiStrings(tester), isEmpty);
  });

  testWidgets(
    'credential issuance flow does not expose Chinese UI in English',
    (tester) async {
      await _pumpLocalizedScreen(
        tester,
        CredentialIssuanceWizard(
          holderDid: 'did:plc:abcdefghijklmnop',
          walletRepository: InMemoryWalletRepository(),
        ),
        locale: const Locale('en'),
      );

      expect(_cjkUiStrings(tester), isEmpty);

      await tester.tap(find.text('Email OTP / Legacy'));
      await tester.pumpAndSettle();
      expect(_cjkUiStrings(tester), isEmpty);

      await tester.tap(find.text('Passport NFC'));
      await tester.pumpAndSettle();
      expect(_cjkUiStrings(tester), isEmpty);

      await tester.tap(find.text('TW Identity Verification'));
      await tester.pumpAndSettle();
      expect(_cjkUiStrings(tester), isEmpty);
    },
  );

  testWidgets('identity, profile, and content detail screens stay English', (
    tester,
  ) async {
    await _pumpLocalizedScreen(
      tester,
      PasskeysRegistrationScreen(onRegistered: (did, handle) {}),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalizedScreen(
      tester,
      const ProfileScreen(),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalizedScreen(
      tester,
      NoteEditorScreen(
        authorDid: 'did:plc:alice',
        boardId: 'board-1',
        threadId: 'thread-1',
        threadTitle: 'Field notes',
        atProtoClient: AtProtoClient(baseUrl: 'http://unused.local'),
      ),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    final note = ContentItem(
      id: 'note-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.note,
      title: 'Field notes',
      body: 'The forest floor is not empty.',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 8, 10, 30),
      updatedAt: DateTime.utc(2026, 5, 8, 11, 45),
    );
    final sourceMurmur = ContentItem(
      id: 'murmur-1',
      authorDid: 'did:plc:alice',
      mode: ContentMode.murmur,
      body: 'A small observation from yesterday.',
      status: ContentStatus.active,
      visibility: ContentVisibility.private,
      createdAt: DateTime.utc(2026, 5, 7, 9),
      updatedAt: DateTime.utc(2026, 5, 7, 9),
    );

    await _pumpLocalizedScreen(
      tester,
      NoteDetailScreen(note: note, sourceMurmurs: [sourceMurmur]),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalizedScreen(
      tester,
      MurmurDetailScreen(murmur: sourceMurmur),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);
  });

  testWidgets('verifier consent and review sheets stay English', (
    tester,
  ) async {
    await _pumpLocalizedScreen(
      tester,
      WalletVerifierConsentScreen(
        holderDid: 'did:key:z6Mkholder',
        request: Oid4vpAuthorizationRequest.parse(_requestUri()),
        presentationService: _FakeOid4vpPresentationService(),
        now: () => DateTime.utc(2026, 5, 30, 10),
      ),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalizedScreen(
      tester,
      const AiProviderSetupSheet(),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalizedScreen(
      tester,
      SummaryReviewSheet(
        summary: 'Short summary',
        sourceLabels: const ['Field notes'],
        onSaveAsNote: (_) async {},
      ),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalizedScreen(
      tester,
      TransformationReviewSheet(
        title: 'Draft',
        body: 'Body text',
        sourceLabels: const ['Field notes'],
        containsPrivateSource: true,
        onAccept: (_, _) async {},
      ),
      locale: const Locale('en'),
    );
    expect(_cjkUiStrings(tester), isEmpty);

    await _pumpLocalized(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showContentDistributionSheet(
            context: context,
            current: const ContentDistributionChoice(
              visibility: ContentVisibility.private,
              distributionPreference: DistributionPreference.localOnly,
            ),
            subjectLabel: 'this murmur',
          ),
          child: const Text('Open'),
        ),
      ),
      locale: const Locale('en'),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_cjkUiStrings(tester), isEmpty);
  });
}

void _ignoreFilter(FeedFilter value) {}

Future<void> _pumpLocalized(
  WidgetTester tester,
  Widget child, {
  required Locale locale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _pumpLocalizedScreen(
  WidgetTester tester,
  Widget child, {
  required Locale locale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  );
}

List<String> _cjkUiStrings(WidgetTester tester) {
  final strings = <String>{};
  final cjk = RegExp(r'[\u3400-\u9FFF\u3000-\u303F\uFF00-\uFFEF]');

  void add(String? value) {
    if (value == null || value.isEmpty) return;
    if (cjk.hasMatch(value)) strings.add(value);
  }

  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Text(:final data):
        add(data);
      case RichText(:final text):
        add(text.toPlainText());
      case Tooltip(:final message):
        add(message);
      case Semantics(:final properties):
        add(properties.label);
        add(properties.hint);
        add(properties.value);
    }
  }

  return strings.toList()..sort();
}

String _requestUri() {
  final definition = {
    'id': 'pd-humanity',
    'input_descriptors': [
      {
        'id': 'humanity-vc',
        'constraints': {
          'fields': [
            {
              'path': [r'$.type'],
              'filter': {
                'type': 'array',
                'contains': {'const': 'TrisAuraHumanityCredential'},
              },
            },
            {
              'path': [r'$.credentialSubject.humanVerified'],
            },
          ],
        },
      },
    ],
  };
  return Uri(
    scheme: 'openid4vp',
    host: 'authorize',
    queryParameters: {
      'client_id': 'https://verifier.example',
      'response_type': 'vp_token',
      'response_mode': 'direct_post',
      'response_uri': 'https://verifier.example/direct_post',
      'nonce': 'nonce-123',
      'presentation_definition': jsonEncode(definition),
    },
  ).toString();
}

class _FakeOid4vpPresentationService implements Oid4vpPresentationApprover {
  @override
  Future<Oid4vpSubmissionResult> approve({
    required String holderDid,
    required Oid4vpAuthorizationRequest request,
    required DateTime now,
  }) async {
    return const Oid4vpSubmissionResult(
      credentialId: 'urn:uuid:test-humanity',
      verifierAudience: 'https://verifier.example',
    );
  }
}
