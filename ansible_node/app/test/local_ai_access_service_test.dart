import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ansible_node/services/local_ai_access_service.dart';

void main() {
  late Directory tempDir;
  late LocalAiAccessService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_ai_access_test');
    service = LocalAiAccessService(
      dataDirectoryProvider: () async => tempDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File grantFile() =>
      File(p.join(tempDir.path, LocalAiAccessService.grantFileName));

  test('enable writes a grant matching the ansible_mcp schema (golden)', () async {
    // Golden guard for the cross-language contract with
    // ansible_mcp/src/grant.rs — if this shape changes, the Rust side must
    // change in the same commit.
    final now = DateTime.utc(2026, 7, 14, 12);
    await service.enable(
      localAuthorDids: ['did:key:local'],
      boardScope: const LocalAiBoardScope.boards(['b-dev', 'b-news']),
      includeMurmurs: true,
      now: now,
      grantId: 'golden-grant',
    );

    final json =
        jsonDecode(await grantFile().readAsString()) as Map<String, dynamic>;
    expect(json, {
      'grant_id': 'golden-grant',
      'created_at': '2026-07-14T12:00:00.000Z',
      'expires_at': '2026-10-12T12:00:00.000Z',
      'local_author_dids': ['did:key:local'],
      'scopes': {
        'boards': ['b-dev', 'b-news'],
        'include_murmurs': true,
        'include_follow_feed': false,
      },
    });
  });

  test('all-boards scope serializes as the string "all"', () async {
    await service.enable(
      localAuthorDids: ['did:key:local'],
      boardScope: const LocalAiBoardScope.all(),
    );
    final json =
        jsonDecode(await grantFile().readAsString()) as Map<String, dynamic>;
    expect((json['scopes'] as Map)['boards'], 'all');
  });

  test('currentGrant round-trips and expiry reads as disabled', () async {
    expect(await service.currentGrant(), isNull);

    await service.enable(
      localAuthorDids: ['did:key:local'],
      boardScope: const LocalAiBoardScope.boards(['b-dev']),
      now: DateTime.utc(2026, 7, 14),
    );
    final grant = await service.currentGrant(
      now: DateTime.utc(2026, 7, 15),
    );
    expect(grant, isNotNull);
    expect(grant!.boardScope.boardIds, ['b-dev']);
    expect(grant.includeMurmurs, isFalse);

    // 90-day default expiry: one day past it reads as disabled.
    expect(
      await service.currentGrant(now: DateTime.utc(2026, 10, 13)),
      isNull,
    );
  });

  test('malformed grant file reads as disabled, not a crash', () async {
    await grantFile().writeAsString('{ not json');
    expect(await service.currentGrant(), isNull);
  });

  test('revoke deletes the grant file', () async {
    await service.enable(
      localAuthorDids: ['did:key:local'],
      boardScope: const LocalAiBoardScope.all(),
    );
    expect(await grantFile().exists(), isTrue);
    await service.revoke();
    expect(await grantFile().exists(), isFalse);
    // Revoking again is a no-op.
    await service.revoke();
  });

  test('recentAccess tails the audit log newest-first and skips torn lines',
      () async {
    final log = File(p.join(tempDir.path, LocalAiAccessService.auditFileName));
    await log.writeAsString(
      '${jsonEncode({'ts': '2026-07-14T01:00:00Z', 'tool': 'list_boards', 'row_count': 2})}\n'
      'garbage-line\n'
      '${jsonEncode({'ts': '2026-07-14T02:00:00Z', 'tool': 'get_thread', 'row_count': 7})}\n',
    );
    final entries = await service.recentAccess(limit: 10);
    expect(entries, hasLength(2));
    expect(entries.first.tool, 'get_thread');
    expect(entries.first.rowCount, 7);
    expect(entries.last.tool, 'list_boards');
  });

  test('setup snippets bake in the data dir path', () async {
    final code = await service.claudeCodeSnippet();
    expect(code, contains('--data-dir "${tempDir.path}"'));
    final json = await service.mcpJsonSnippet();
    final parsed = jsonDecode(json) as Map<String, dynamic>;
    final server =
        ((parsed['mcpServers'] as Map)['ansible'] as Map).cast<String, Object?>();
    expect(server['args'], ['serve', '--data-dir', tempDir.path]);
  });
}
