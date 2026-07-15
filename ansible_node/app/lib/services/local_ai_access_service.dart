import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_policy_service.dart';

/// Manages the Local AI Access grant file consumed by the `ansible-mcp`
/// binary (plan T-301).
///
/// The grant is the user's explicit, revocable consent record for exposing
/// scoped forum content to local MCP-capable AI clients — the binary fails
/// closed without it. Schema must stay in lockstep with
/// `ansible_mcp/src/grant.rs`; a golden test guards it
/// (`test/local_ai_access_service_test.dart`).
///
/// Spec: docs/superpowers/specs/2026-07-14-local-mcp-agent-access-design.md
class LocalAiAccessService {
  LocalAiAccessService({Future<Directory> Function()? dataDirectoryProvider})
    : _dataDirectoryProvider = dataDirectoryProvider ?? _defaultDataDirectory;

  static const grantFileName = 'mcp_access_grant.json';
  static const auditFileName = 'mcp_access_audit.log';
  static const defaultGrantDuration = Duration(days: 90);

  final Future<Directory> Function() _dataDirectoryProvider;

  /// Same resolution chain the app uses to open `ansible.db`
  /// (`main.dart`): backup-policy canonical directory, falling back to the
  /// platform app-support directory.
  static Future<Directory> _defaultDataDirectory() async {
    try {
      final paths = await BackupPolicyService().prepareStorage();
      return paths.canonicalDirectory;
    } catch (_) {
      return getApplicationSupportDirectory();
    }
  }

  Future<Directory> dataDirectory() => _dataDirectoryProvider();

  Future<File> _grantFile() async =>
      File(p.join((await dataDirectory()).path, grantFileName));

  /// The active grant, or null when disabled/expired/unreadable (the binary
  /// treats those identically, so the UI should too).
  Future<LocalAiAccessGrant?> currentGrant({DateTime? now}) async {
    final file = await _grantFile();
    if (!await file.exists()) return null;
    try {
      final grant = LocalAiAccessGrant.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      final reference = now ?? DateTime.now().toUtc();
      if (!grant.expiresAt.isAfter(reference)) return null;
      return grant;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Writes a fresh grant (enable or renew). Atomic: temp file + rename, so
  /// the binary never observes a partial grant.
  Future<LocalAiAccessGrant> enable({
    required List<String> localAuthorDids,
    required LocalAiBoardScope boardScope,
    bool includeMurmurs = false,
    bool includeFollowFeed = false,
    DateTime? now,
    String? grantId,
  }) async {
    final created = (now ?? DateTime.now()).toUtc();
    final grant = LocalAiAccessGrant(
      grantId: grantId ?? _newGrantId(created),
      createdAt: created,
      expiresAt: created.add(defaultGrantDuration),
      localAuthorDids: List.unmodifiable(localAuthorDids),
      boardScope: boardScope,
      includeMurmurs: includeMurmurs,
      includeFollowFeed: includeFollowFeed,
    );
    final file = await _grantFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(grant.toJson()),
      flush: true,
    );
    await temp.rename(file.path);
    return grant;
  }

  /// Revocation = deleting the grant file; the binary re-reads it on every
  /// tool call, so this takes effect immediately.
  Future<void> revoke() async {
    final file = await _grantFile();
    if (await file.exists()) await file.delete();
  }

  /// Tail of the binary's audit log (metadata only — the binary never logs
  /// content), newest first.
  Future<List<LocalAiAccessAuditEntry>> recentAccess({int limit = 20}) async {
    final dir = await dataDirectory();
    final file = File(p.join(dir.path, auditFileName));
    if (!await file.exists()) return const [];
    final lines = const LineSplitter().convert(await file.readAsString());
    final entries = <LocalAiAccessAuditEntry>[];
    for (final line in lines.reversed) {
      if (entries.length >= limit) break;
      if (line.trim().isEmpty) continue;
      try {
        entries.add(
          LocalAiAccessAuditEntry.fromJson(
            jsonDecode(line) as Map<String, dynamic>,
          ),
        );
      } on FormatException {
        // Skip torn/rotated lines rather than hiding the rest.
      }
    }
    return entries;
  }

  /// Path of the `ansible-mcp` helper bundled inside the desktop app
  /// (`Elix.app/Contents/Helpers/ansible-mcp`, copied by the "Bundle
  /// ansible-mcp" Xcode build phase), or null when this build ships without
  /// it. Bundling keeps the binary in lockstep with the DB schema, so the
  /// snippets prefer it over whatever `ansible-mcp` happens to be on PATH.
  ///
  /// Injectable for tests via [bundledBinaryPathOverride].
  static String? Function() bundledBinaryPathOverride = _macosBundledBinary;

  static String? bundledBinaryPath() => bundledBinaryPathOverride();

  static String? _macosBundledBinary() {
    if (!Platform.isMacOS) return null;
    // resolvedExecutable = <app>.app/Contents/MacOS/<exe>
    final contents = File(Platform.resolvedExecutable).parent.parent;
    final helper = File(p.join(contents.path, 'Helpers', 'ansible-mcp'));
    return helper.existsSync() ? helper.path : null;
  }

  /// Claude Code CLI setup command with the data dir baked in (plan D-4).
  /// Defaults to the bundled helper when present, else `ansible-mcp` on PATH.
  Future<String> claudeCodeSnippet({String? binaryPath}) async {
    final bin = binaryPath ?? bundledBinaryPath() ?? 'ansible-mcp';
    final dir = await dataDirectory();
    return 'claude mcp add ansible -- "$bin" serve --data-dir "${dir.path}"';
  }

  /// Generic stdio-server JSON block (Claude Desktop and most MCP clients).
  /// Defaults to the bundled helper when present, else `ansible-mcp` on PATH.
  Future<String> mcpJsonSnippet({String? binaryPath}) async {
    final bin = binaryPath ?? bundledBinaryPath() ?? 'ansible-mcp';
    final dir = await dataDirectory();
    return const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {
        'ansible': {
          'command': bin,
          'args': ['serve', '--data-dir', dir.path],
        },
      },
    });
  }

  static String _newGrantId(DateTime now) {
    final random = now.microsecondsSinceEpoch.toRadixString(36);
    final pid_ = pid.toRadixString(36);
    return 'grant-$random-$pid_';
  }
}

/// `"all"` or an explicit list of board ids — mirrors `BoardScope` in
/// `ansible_mcp/src/grant.rs`.
class LocalAiBoardScope {
  const LocalAiBoardScope.all() : boardIds = null;
  const LocalAiBoardScope.boards(List<String> this.boardIds);

  /// Null means all boards.
  final List<String>? boardIds;

  bool get isAll => boardIds == null;

  Object toJson() => boardIds ?? 'all';

  static LocalAiBoardScope fromJson(Object? value) {
    if (value == 'all') return const LocalAiBoardScope.all();
    if (value is List) {
      return LocalAiBoardScope.boards(value.cast<String>().toList());
    }
    throw const FormatException('boards scope must be "all" or a list');
  }
}

class LocalAiAccessGrant {
  const LocalAiAccessGrant({
    required this.grantId,
    required this.createdAt,
    required this.expiresAt,
    required this.localAuthorDids,
    required this.boardScope,
    required this.includeMurmurs,
    required this.includeFollowFeed,
  });

  final String grantId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> localAuthorDids;
  final LocalAiBoardScope boardScope;
  final bool includeMurmurs;
  final bool includeFollowFeed;

  Map<String, dynamic> toJson() => {
    'grant_id': grantId,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'local_author_dids': localAuthorDids,
    'scopes': {
      'boards': boardScope.toJson(),
      'include_murmurs': includeMurmurs,
      'include_follow_feed': includeFollowFeed,
    },
  };

  static LocalAiAccessGrant fromJson(Map<String, dynamic> json) {
    final scopes = json['scopes'] as Map<String, dynamic>? ?? const {};
    return LocalAiAccessGrant(
      grantId: json['grant_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      localAuthorDids:
          (json['local_author_dids'] as List?)?.cast<String>() ?? const [],
      boardScope: LocalAiBoardScope.fromJson(scopes['boards']),
      includeMurmurs: scopes['include_murmurs'] as bool? ?? false,
      includeFollowFeed: scopes['include_follow_feed'] as bool? ?? false,
    );
  }
}

class LocalAiAccessAuditEntry {
  const LocalAiAccessAuditEntry({
    required this.timestamp,
    required this.tool,
    required this.rowCount,
  });

  final DateTime? timestamp;
  final String tool;
  final int rowCount;

  static LocalAiAccessAuditEntry fromJson(Map<String, dynamic> json) {
    return LocalAiAccessAuditEntry(
      timestamp: DateTime.tryParse(json['ts'] as String? ?? ''),
      tool: json['tool'] as String? ?? '?',
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
    );
  }
}
