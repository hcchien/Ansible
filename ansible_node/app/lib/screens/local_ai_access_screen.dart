import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_l10n.dart';
import '../services/local_ai_access_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

/// Settings → Local AI Access (plan T-302/T-303).
///
/// The consent surface for the `ansible-mcp` read-only local MCP server.
/// Enabling writes the grant file the binary requires (fail-closed on its
/// side); disabling deletes it, which revokes access immediately. Desktop
/// only — the caller gates the entry row.
class LocalAiAccessScreen extends StatefulWidget {
  const LocalAiAccessScreen({
    super.key,
    required this.db,
    required this.did,
    this.service,
  });

  final AppDatabase db;
  final String did;

  /// Injectable for tests; defaults to the production data-dir resolution.
  final LocalAiAccessService? service;

  @override
  State<LocalAiAccessScreen> createState() => _LocalAiAccessScreenState();
}

class _LocalAiAccessScreenState extends State<LocalAiAccessScreen> {
  late final LocalAiAccessService _service =
      widget.service ?? LocalAiAccessService();

  bool _loading = true;
  LocalAiAccessGrant? _grant;
  List<Board> _boards = const [];
  List<LocalAiAccessAuditEntry> _recentAccess = const [];
  String? _claudeCodeSnippet;
  String? _mcpJsonSnippet;
  String? _bundledBinary;

  // Draft scope selections while disabled.
  bool _allBoards = false;
  final Set<String> _selectedBoardIds = <String>{};
  bool _includeMurmurs = false;
  bool _includeFollowFeed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final grant = await _service.currentGrant();
    final boards = await DriftBoardRepository(widget.db).list();
    final recent = grant != null
        ? await _service.recentAccess()
        : const <LocalAiAccessAuditEntry>[];
    final claudeCode = grant != null
        ? await _service.claudeCodeSnippet()
        : null;
    final mcpJson = grant != null ? await _service.mcpJsonSnippet() : null;
    final bundledBinary = LocalAiAccessService.bundledBinaryPath();
    if (!mounted) return;
    setState(() {
      _bundledBinary = bundledBinary;
      _grant = grant;
      _boards = boards.where((b) => !b.isDeleted).toList();
      _recentAccess = recent;
      _claudeCodeSnippet = claudeCode;
      _mcpJsonSnippet = mcpJson;
      if (grant != null) {
        _allBoards = grant.boardScope.isAll;
        _selectedBoardIds
          ..clear()
          ..addAll(grant.boardScope.boardIds ?? const []);
        _includeMurmurs = grant.includeMurmurs;
        _includeFollowFeed = grant.includeFollowFeed;
      }
      _loading = false;
    });
  }

  Future<void> _enable() async {
    await _service.enable(
      localAuthorDids: [widget.did],
      boardScope: _allBoards
          ? const LocalAiBoardScope.all()
          : LocalAiBoardScope.boards(_selectedBoardIds.toList()..sort()),
      includeMurmurs: _includeMurmurs,
      includeFollowFeed: _includeFollowFeed,
    );
    await _reload();
  }

  Future<void> _revoke() async {
    await _service.revoke();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '本機 AI 存取', en: 'Local AI Access'),
      leadingLabel: context.uiCopy(zh: '設定', en: 'Settings'),
      onLeading: () => Navigator.of(context).maybePop(),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                _disclosureCard(context),
                const SizedBox(height: 16),
                if (_grant == null) ..._disabledBody(context),
                if (_grant != null) ..._enabledBody(context, _grant!),
              ],
            ),
    );
  }

  /// The consent disclosure (spec wording): names the cloud-vendor
  /// consequence before anything can be enabled.
  Widget _disclosureCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AnsibleDesign.ruleSoft),
      ),
      child: Text(
        context.uiCopy(
          zh:
              '啟用後，你選擇範圍內的內容可被這台電腦上的 AI 客戶端讀取。'
              '若 AI 客戶端連接雲端服務（如 Claude、ChatGPT），這些內容會被'
              '傳送到該服務商的伺服器。存取為唯讀，且不含私訊、錢包憑證與'
              '身分金鑰。可隨時停用，立即生效。',
          en:
              'When enabled, content in the scopes you select becomes readable '
              'by AI clients on this computer. Cloud-backed clients (e.g. '
              'Claude, ChatGPT) will send that content to their vendor\'s '
              'servers. Access is read-only and never includes messages, '
              'wallet credentials, or identity keys. Disable at any time; it '
              'takes effect immediately.',
        ),
        style: const TextStyle(
          fontFamily: AnsibleDesign.sans,
          fontSize: 13,
          height: 1.5,
          color: AnsibleDesign.ink,
        ),
      ),
    );
  }

  List<Widget> _disabledBody(BuildContext context) {
    return [
      _sectionLabel(context.uiCopy(zh: '讀取範圍', en: 'READ SCOPE')),
      SwitchListTile(
        key: const Key('local_ai_all_boards_switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.uiCopy(zh: '所有看板', en: 'All boards')),
        value: _allBoards,
        onChanged: (v) => setState(() => _allBoards = v),
      ),
      if (!_allBoards)
        ..._boards.map(
          (board) => CheckboxListTile(
            key: Key('local_ai_board_${board.id}'),
            contentPadding: const EdgeInsets.only(left: 12),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(board.title),
            subtitle: Text(board.slug),
            value: _selectedBoardIds.contains(board.id),
            onChanged: (checked) => setState(() {
              if (checked == true) {
                _selectedBoardIds.add(board.id);
              } else {
                _selectedBoardIds.remove(board.id);
              }
            }),
          ),
        ),
      SwitchListTile(
        key: const Key('local_ai_murmurs_switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          context.uiCopy(zh: '包含 murmur / 筆記', en: 'Include murmurs / notes'),
        ),
        subtitle: Text(
          context.uiCopy(
            zh: '他人的私密或僅本機內容永不包含',
            en: "Other authors' private or local-only items are never included",
          ),
        ),
        value: _includeMurmurs,
        onChanged: (v) => setState(() => _includeMurmurs = v),
      ),
      SwitchListTile(
        key: const Key('local_ai_follow_feed_switch'),
        contentPadding: EdgeInsets.zero,
        title: Text(context.uiCopy(zh: '包含追蹤動態', en: 'Include follow feed')),
        value: _includeFollowFeed,
        onChanged: (v) => setState(() => _includeFollowFeed = v),
      ),
      const SizedBox(height: 18),
      FilledButton(
        key: const Key('local_ai_enable_button'),
        onPressed: _allBoards || _selectedBoardIds.isNotEmpty ? _enable : null,
        child: Text(
          context.uiCopy(zh: '啟用本機 AI 存取', en: 'Enable Local AI Access'),
        ),
      ),
    ];
  }

  List<Widget> _enabledBody(BuildContext context, LocalAiAccessGrant grant) {
    final expires = grant.expiresAt.toLocal().toString().split('.').first;
    final scopeSummary = grant.boardScope.isAll
        ? context.uiCopy(zh: '所有看板', en: 'all boards')
        : context.uiCopy(
            zh: '${grant.boardScope.boardIds!.length} 個看板',
            en: '${grant.boardScope.boardIds!.length} board(s)',
          );
    return [
      _sectionLabel(context.uiCopy(zh: '狀態', en: 'STATUS')),
      ListTile(
        key: const Key('local_ai_status_tile'),
        contentPadding: EdgeInsets.zero,
        title: Text(
          context.uiCopy(
            zh: '已啟用 · $scopeSummary',
            en: 'Enabled · $scopeSummary',
          ),
        ),
        subtitle: Text(
          context.uiCopy(zh: '有效至 $expires', en: 'Valid until $expires'),
        ),
      ),
      const SizedBox(height: 8),
      _sectionLabel(context.uiCopy(zh: '連接 AI 客戶端', en: 'CONNECT A CLIENT')),
      ListTile(
        key: const Key('local_ai_binary_tile'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(
          _bundledBinary != null
              ? context.uiCopy(
                  zh: 'MCP 伺服器：隨附於 App，由 AI 客戶端自動啟動',
                  en: 'MCP server: bundled with the app, launched automatically by the AI client',
                )
              : context.uiCopy(
                  zh: 'MCP 伺服器：此版本未隨附，將使用 PATH 上的 ansible-mcp',
                  en: 'MCP server: not bundled in this build; uses ansible-mcp from PATH',
                ),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: _bundledBinary == null
            ? null
            : Text(
                _bundledBinary!,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                ),
              ),
      ),
      if (_claudeCodeSnippet != null)
        _snippetCard(
          context,
          label: 'Claude Code',
          snippet: _claudeCodeSnippet!,
          keyName: 'local_ai_snippet_claude_code',
        ),
      if (_mcpJsonSnippet != null)
        _snippetCard(
          context,
          label: context.uiCopy(
            zh: 'Claude Desktop / 其他 MCP 客戶端',
            en: 'Claude Desktop / other MCP clients',
          ),
          snippet: _mcpJsonSnippet!,
          keyName: 'local_ai_snippet_mcp_json',
        ),
      const SizedBox(height: 8),
      _sectionLabel(context.uiCopy(zh: '最近存取', en: 'RECENT ACCESS')),
      if (_recentAccess.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            context.uiCopy(zh: '尚無存取紀錄', en: 'No access recorded yet'),
            style: const TextStyle(color: AnsibleDesign.inkMuted, fontSize: 13),
          ),
        ),
      ..._recentAccess.map(
        (entry) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            entry.tool,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 13,
            ),
          ),
          trailing: Text(
            '${entry.rowCount} rows',
            style: const TextStyle(color: AnsibleDesign.inkMuted, fontSize: 12),
          ),
          subtitle: entry.timestamp == null
              ? null
              : Text(entry.timestamp!.toLocal().toString().split('.').first),
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton(
        key: const Key('local_ai_renew_button'),
        onPressed: _enable,
        child: Text(context.uiCopy(zh: '續期 90 天', en: 'Renew for 90 days')),
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(
        key: const Key('local_ai_revoke_button'),
        style: FilledButton.styleFrom(foregroundColor: AnsibleDesign.danger),
        onPressed: _revoke,
        child: Text(
          context.uiCopy(zh: '停用並撤銷存取', en: 'Disable and revoke access'),
        ),
      ),
    ];
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 11,
          letterSpacing: 1.3,
          color: AnsibleDesign.ochre,
        ),
      ),
    );
  }

  Widget _snippetCard(
    BuildContext context, {
    required String label,
    required String snippet,
    required String keyName,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ),
              IconButton(
                key: Key('${keyName}_copy'),
                icon: const Icon(Icons.copy, size: 16),
                tooltip: context.uiCopy(zh: '複製', en: 'Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: snippet));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.uiCopy(zh: '已複製', en: 'Copied')),
                    ),
                  );
                },
              ),
            ],
          ),
          SelectableText(
            snippet,
            key: Key(keyName),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
