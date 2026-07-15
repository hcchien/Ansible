import 'dart:io';

import 'package:ansible_store/ansible_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ansible_node/screens/local_ai_access_screen.dart';
import 'package:ansible_node/screens/settings_home_screen.dart';
import 'package:ansible_node/services/local_ai_access_service.dart';

/// In-memory service: widget tests run in a fake-async zone where real file
/// I/O never completes (the loading spinner would spin forever). File-level
/// behavior is covered by local_ai_access_service_test.dart.
class _MemoryLocalAiAccessService extends LocalAiAccessService {
  _MemoryLocalAiAccessService()
    : super(
        dataDirectoryProvider: () async => Directory('/unused-in-memory'),
      );

  LocalAiAccessGrant? grant;

  @override
  Future<LocalAiAccessGrant?> currentGrant({DateTime? now}) async => grant;

  @override
  Future<LocalAiAccessGrant> enable({
    required List<String> localAuthorDids,
    required LocalAiBoardScope boardScope,
    bool includeMurmurs = false,
    bool includeFollowFeed = false,
    DateTime? now,
    String? grantId,
  }) async {
    final created = (now ?? DateTime.now()).toUtc();
    grant = LocalAiAccessGrant(
      grantId: grantId ?? 'memory-grant',
      createdAt: created,
      expiresAt: created.add(LocalAiAccessService.defaultGrantDuration),
      localAuthorDids: localAuthorDids,
      boardScope: boardScope,
      includeMurmurs: includeMurmurs,
      includeFollowFeed: includeFollowFeed,
    );
    return grant!;
  }

  @override
  Future<void> revoke() async {
    grant = null;
  }

  @override
  Future<List<LocalAiAccessAuditEntry>> recentAccess({int limit = 20}) async =>
      const [];

  @override
  Future<String> claudeCodeSnippet({String? binaryPath}) async =>
      'claude mcp add ansible -- ansible-mcp serve --data-dir "/data"';

  @override
  Future<String> mcpJsonSnippet({String? binaryPath}) async =>
      '{"mcpServers": {}}';
}

void main() {
  late AppDatabase db;
  late _MemoryLocalAiAccessService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = _MemoryLocalAiAccessService();
    await DriftBoardRepository(db).create(
      Board(
        id: 'b-dev',
        slug: 'dev',
        title: 'Development',
        description: null,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(LocalAiAccessScreen(db: db, did: 'did:key:local', service: service)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('enable flow writes grant with selected board scope',
      (tester) async {
    await pumpScreen(tester);

    // Disabled state: enable button is present but inert until a scope exists.
    final enableButton = find.byKey(const Key('local_ai_enable_button'));
    expect(enableButton, findsOneWidget);
    expect(tester.widget<FilledButton>(enableButton).onPressed, isNull);

    await tester.tap(find.byKey(const Key('local_ai_board_b-dev')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(enableButton);
    await tester.tap(enableButton);
    await tester.pumpAndSettle();

    final grant = service.grant;
    expect(grant, isNotNull);
    expect(grant!.boardScope.boardIds, ['b-dev']);
    expect(grant.localAuthorDids, ['did:key:local']);
    expect(grant.includeMurmurs, isFalse);

    // Enabled state shows status and setup snippets with the data dir.
    expect(find.byKey(const Key('local_ai_status_tile')), findsOneWidget);
    expect(
      find.byKey(const Key('local_ai_snippet_claude_code')),
      findsOneWidget,
    );
  });

  testWidgets('revoke deletes the grant and returns to the consent state',
      (tester) async {
    await service.enable(
      localAuthorDids: ['did:key:local'],
      boardScope: const LocalAiBoardScope.all(),
    );
    await pumpScreen(tester);

    // The revoke button sits at the end of a lazy ListView; scroll it into
    // existence first.
    final revokeButton = find.byKey(const Key('local_ai_revoke_button'));
    await tester.scrollUntilVisible(
      revokeButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(revokeButton);
    await tester.pumpAndSettle();

    expect(service.grant, isNull);
    expect(find.byKey(const Key('local_ai_enable_button')), findsOneWidget);
  });

  testWidgets('settings row hidden when showLocalAiAccess is false',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        SettingsHomeScreen(
          db: db,
          did: 'did:key:local',
          showLocalAiAccess: false,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('settings_local_ai_access_row')),
      findsNothing,
    );
  });

  testWidgets('settings row visible when showLocalAiAccess is true',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        SettingsHomeScreen(
          db: db,
          did: 'did:key:local',
          showLocalAiAccess: true,
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_local_ai_access_row')),
      300,
    );
    expect(
      find.byKey(const Key('settings_local_ai_access_row')),
      findsOneWidget,
    );
  });
}
