import 'dart:convert';

import 'package:ansible_node/screens/terms_acceptance_screen.dart';
import 'package:ansible_node/services/blocked_author_store.dart';
import 'package:ansible_node/services/external_url_launcher.dart';
import 'package:ansible_node/services/safety_actions.dart';
import 'package:ansible_node/services/terms_acceptance_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('terms acceptance is versioned and persisted', () async {
    const store = TermsAcceptanceStore();

    expect(await store.hasAcceptedCurrent(), isFalse);
    await store.acceptCurrent();
    expect(await store.hasAcceptedCurrent(), isTrue);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(TermsAcceptanceStore.preferenceKey),
      TermsAcceptanceStore.currentVersion,
    );
  });

  testWidgets('terms gate requires explicit agreement before continuing', (
    tester,
  ) async {
    var accepted = false;
    final launcher = _RecordingLauncher();
    await tester.pumpWidget(
      MaterialApp(
        home: TermsAcceptanceScreen(
          onAccepted: () => accepted = true,
          urlLauncher: launcher,
          legalBaseUrl: 'https://elix.cool/',
        ),
      ),
    );

    final continueButton = find.byKey(const Key('accept_terms_continue'));
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.tap(find.byKey(const Key('open_terms_link')));
    await tester.pump();
    expect(launcher.opened.single, Uri.parse('https://elix.cool/terms'));

    await tester.tap(find.byKey(const Key('accept_terms_checkbox')));
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);

    await tester.tap(continueButton);
    await tester.pump();
    expect(accepted, isTrue);
    expect(await const TermsAcceptanceStore().hasAcceptedCurrent(), isTrue);
  });

  test('blocked authors are isolated by owner and reversible', () async {
    const store = BlockedAuthorStore();
    await store.block('did:elix:alice', 'did:elix:bob');

    expect(await store.isBlocked('did:elix:alice', 'did:elix:bob'), isTrue);
    expect(await store.isBlocked('did:elix:carol', 'did:elix:bob'), isFalse);

    await store.unblock('did:elix:alice', 'did:elix:bob');
    expect(await store.isBlocked('did:elix:alice', 'did:elix:bob'), isFalse);
  });

  test('block is durable before developer notification is attempted', () async {
    const store = BlockedAuthorStore();
    final actions = SafetyActions(
      blockedAuthors: store,
      transport: _FailingTransport(),
      signer: (_) async => 'signature',
      relayBaseUrl: 'https://relay.elix.cool',
    );

    await expectLater(
      actions.blockAndReport(
        reporterDid: 'did:elix:alice',
        subjectDid: 'did:elix:bob',
        targetKind: 'post',
        targetRef: 'post-1',
        reasonCode: 'harassment',
      ),
      throwsA(isA<StateError>()),
    );

    expect(await store.isBlocked('did:elix:alice', 'did:elix:bob'), isTrue);
  });

  test(
    'safety reports are canonical, signed, and sent to the operator',
    () async {
      final transport = _RecordingTransport();
      List<int>? signedPayload;
      final actions = SafetyActions(
        transport: transport,
        signer: (payload) async {
          signedPayload = payload;
          return 'signed-proof';
        },
        relayBaseUrl: 'https://relay.elix.cool/',
      );

      await actions.reportContent(
        reporterDid: 'did:elix:alice',
        subjectDid: 'did:elix:bob',
        targetKind: 'comment',
        targetRef: 'comment-1',
        reasonCode: 'spam',
        note: 'Repeated promotions',
      );

      final body = transport.body!;
      expect(body['type'], 'io.trisaura.safety.report');
      expect(body['action'], 'report_content');
      expect(body['author_did'], 'did:elix:alice');
      expect(body['target_relay'], 'https://relay.elix.cool/');
      expect(body['signature'], 'signed-proof');
      expect(body['report'], containsPair('reason_code', 'spam'));
      expect(utf8.decode(signedPayload!), isNot(contains('signed-proof')));
    },
  );
}

class _RecordingLauncher implements ExternalUrlLauncher {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

class _RecordingTransport implements SafetyReportTransport {
  Map<String, Object?>? body;

  @override
  Future<void> send(Map<String, Object?> body) async {
    this.body = body;
  }
}

class _FailingTransport implements SafetyReportTransport {
  @override
  Future<void> send(Map<String, Object?> body) async {
    throw StateError('offline');
  }
}
