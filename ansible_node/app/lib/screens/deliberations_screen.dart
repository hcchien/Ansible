import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_l10n.dart';
import '../services/board_access_presentation_service.dart';
import '../services/deliberation_export_cache_service.dart';
import '../services/forum_host_client.dart';
import '../services/user_presence_verifier.dart';
import '../theme/ansible_design.dart';

class DeliberationsScreen extends StatefulWidget {
  const DeliberationsScreen({
    super.key,
    required this.db,
    required this.board,
    required this.localDid,
  });

  final AppDatabase db;
  final Board board;
  final String localDid;

  @override
  State<DeliberationsScreen> createState() => _DeliberationsScreenState();
}

class _DeliberationsScreenState extends State<DeliberationsScreen> {
  HostedBoardProjection? _projection;
  RemoteNode? _host;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final projection = await DriftHostedBoardRepository(
        widget.db,
      ).getProjectionByLocalBoardId(widget.board.id);
      if (projection == null) throw StateError('board_not_hosted');
      final host = await DriftRemoteNodeRepository(
        widget.db,
      ).getById(projection.forumHostId);
      if (host == null) throw StateError('forum_host_unavailable');
      final client = ForumHostClient(baseUrl: host.url);
      try {
        final headers = await _proofHeaders(
          projection: projection,
          hostUrl: host.url,
          method: 'GET',
          path:
              '/api/v1/forum-host/boards/${Uri.encodeComponent(projection.hostedBoardId)}/deliberations',
          action: 'read',
        );
        final items = await client.listDeliberations(
          projection.hostedBoardId,
          headers: headers,
        );
        if (!mounted) return;
        setState(() {
          _projection = projection;
          _host = host;
          _items = items;
          _error = null;
        });
      } finally {
        client.close();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final prompt = TextEditingController();
    String exportMode = 'aggregates_only';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.uiCopy(zh: '新增共識討論', en: 'New deliberation')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('deliberation_title_field'),
                    controller: title,
                    maxLength: 160,
                    decoration: InputDecoration(
                      labelText: context.uiCopy(zh: '主題', en: 'Topic'),
                    ),
                  ),
                  TextField(
                    key: const Key('deliberation_prompt_field'),
                    controller: prompt,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: context.uiCopy(
                        zh: '希望大家一起判斷的問題',
                        en: 'Question for the group',
                      ),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('deliberation_export_mode'),
                    initialValue: exportMode,
                    decoration: InputDecoration(
                      labelText: context.uiCopy(
                        zh: '外部分析資料',
                        en: 'External analysis data',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'no_external_analysis',
                        child: Text(
                          context.uiCopy(zh: '不提供', en: 'No external analysis'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'aggregates_only',
                        child: Text(
                          context.uiCopy(zh: '僅彙總資料', en: 'Aggregates only'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'pseudonymous_matrix',
                        child: Text(
                          context.uiCopy(
                            zh: '允許去識別化回應矩陣',
                            en: 'Allow pseudonymous response matrix',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => exportMode = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.uiCopy(
                      zh: '開始收到回應後，資料分享範圍只能縮小、不能擴大。',
                      en: 'After responses begin, the data-sharing scope can only be narrowed.',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              key: const Key('create_deliberation_submit'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.uiCopy(zh: '建立', en: 'Create')),
            ),
          ],
        ),
      ),
    );
    if (accepted != true ||
        title.text.trim().isEmpty ||
        prompt.text.trim().isEmpty) {
      return;
    }

    final projection = _projection;
    final host = _host;
    if (projection == null || host == null) return;
    final createdAt = DateTime.now().toUtc();
    final unsigned = DeliberationIntentPayload.create(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: host.url,
      boardId: projection.hostedBoardId,
      deliberation: {
        'title': title.text.trim(),
        'prompt': prompt.text.trim(),
        'export_mode': exportMode,
      },
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    await _sendSigned(
      projection: projection,
      host: host,
      method: 'POST',
      path:
          '/api/v1/forum-host/boards/${Uri.encodeComponent(projection.hostedBoardId)}/deliberations',
      action: 'post',
      unsigned: unsigned,
      send: (client, payload, headers) => client.createDeliberation(
        projection.hostedBoardId,
        payload,
        headers: headers,
      ),
    );
    await _load();
  }

  Future<void> _sendSigned({
    required HostedBoardProjection projection,
    required RemoteNode host,
    required String method,
    required String path,
    required String action,
    required Map<String, Object?> unsigned,
    required Future<Object?> Function(
      ForumHostClient,
      Map<String, Object?>,
      Map<String, String>,
    )
    send,
  }) async {
    HardwareAuthenticationSession? session;
    final client = ForumHostClient(baseUrl: host.url);
    try {
      final reason = context.uiCopy(
        zh: '請驗證裝置持有人，以送出共識討論操作。',
        en: 'Authenticate to submit this deliberation action.',
      );
      session = await HardwareAuthenticationSession.begin(
        localizedReason: reason,
      );
      if (session == null &&
          !await LocalDeviceUserPresenceVerifier().verify(reason: reason)) {
        throw StateError('device_auth_cancelled');
      }
      final signer = DidSignerImpl(reuseAuthenticationContext: session != null);
      final headers = await _proofHeaders(
        projection: projection,
        hostUrl: host.url,
        method: method,
        path: path,
        action: action,
        didSigner: signer,
        reuseAuthenticationContext: session != null,
      );
      final signature = await signer.sign(
        utf8.encode(forumHostCanonicalJson(unsigned)),
      );
      await send(client, {...unsigned, 'signature': signature.hex}, headers);
    } finally {
      await session?.close();
      client.close();
    }
  }

  Future<Map<String, String>> _proofHeaders({
    required HostedBoardProjection projection,
    required String hostUrl,
    required String method,
    required String path,
    required String action,
    DidSigner? didSigner,
    bool reuseAuthenticationContext = false,
  }) async {
    final actionPolicy = projection.accessPolicy[action];
    final requirement = actionPolicy is Map
        ? actionPolicy['requirement']
        : null;
    if (requirement == null ||
        requirement == 'public' ||
        requirement == 'posting_policy' ||
        requirement == 'board_moderator') {
      return const {};
    }
    final signer = didSigner ?? DidSignerImpl();
    final access = BoardAccessPresentationService(
      walletRepository: DriftWalletRepository(widget.db),
      didSigner: signer,
    );
    final capability = await access.authorize(
      forumHost: Uri.parse(hostUrl),
      boardId: projection.hostedBoardId,
      action: action,
      reuseAuthenticationContext: reuseAuthenticationContext,
    );
    return access.proofHeaders(
      capability: capability,
      method: method,
      requestUri: Uri.parse(hostUrl).resolve(path),
      scope: action,
      reuseAuthenticationContext: reuseAuthenticationContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.uiCopy(zh: '共識討論', en: 'Deliberations')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _projection == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('create_deliberation_button'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text(context.uiCopy(zh: '新增主題', en: 'New topic')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _items.isEmpty
          ? Center(
              child: Text(
                context.uiCopy(
                  zh: '這個看板還沒有共識討論。',
                  en: 'This board has no deliberations yet.',
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  child: ListTile(
                    key: Key('deliberation_${item['id']}'),
                    leading: const Icon(Icons.hub_outlined),
                    title: Text(item['title']?.toString() ?? ''),
                    subtitle: Text(
                      context.uiCopy(
                        zh: '${item['statement_count'] ?? 0} 則陳述 · ${item['participant_count'] ?? 0} 位參與者',
                        en: '${item['statement_count'] ?? 0} statements · ${item['participant_count'] ?? 0} participants',
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final projection = _projection;
                      final host = _host;
                      if (projection == null || host == null) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DeliberationDetailScreen(
                            db: widget.db,
                            projection: projection,
                            host: host,
                            localDid: widget.localDid,
                            deliberationId: item['id'].toString(),
                          ),
                        ),
                      );
                      await _load();
                    },
                  ),
                );
              },
            ),
    );
  }
}

class DeliberationDetailScreen extends StatefulWidget {
  const DeliberationDetailScreen({
    super.key,
    required this.db,
    required this.projection,
    required this.host,
    required this.localDid,
    required this.deliberationId,
  });

  final AppDatabase db;
  final HostedBoardProjection projection;
  final RemoteNode host;
  final String localDid;
  final String deliberationId;

  @override
  State<DeliberationDetailScreen> createState() =>
      _DeliberationDetailScreenState();
}

class _DeliberationDetailScreenState extends State<DeliberationDetailScreen> {
  Map<String, dynamic>? _deliberation;
  final Map<String, Map<String, String>> _responses = {};
  bool _loading = true;
  String? _error;

  String get _basePath =>
      '/api/v1/forum-host/boards/${Uri.encodeComponent(widget.projection.hostedBoardId)}/deliberations/${Uri.encodeComponent(widget.deliberationId)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final client = ForumHostClient(baseUrl: widget.host.url);
    try {
      final headers = await _accessHeaders(
        action: 'read',
        method: 'GET',
        path: _basePath,
      );
      final body = await client.fetchDeliberation(
        widget.projection.hostedBoardId,
        widget.deliberationId,
        headers: headers,
      );
      if (!mounted) return;
      setState(() {
        _deliberation = Map<String, dynamic>.from(
          body['deliberation'] as Map? ?? const {},
        );
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _vote(String statementId, String stance) async {
    final current = _responses[statementId];
    final createdAt = DateTime.now().toUtc();
    final unsigned = DeliberationIntentPayload.vote(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: widget.host.url,
      boardId: widget.projection.hostedBoardId,
      deliberationId: widget.deliberationId,
      statementId: statementId,
      stance: stance,
      supersedesIntentId: current?['last_intent_id'],
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    final response = await _signedRequest(
      method: 'PUT',
      path: '$_basePath/statements/${Uri.encodeComponent(statementId)}/vote',
      unsigned: unsigned,
      send: (client, payload, headers) => client.castDeliberationVote(
        widget.projection.hostedBoardId,
        widget.deliberationId,
        statementId,
        payload,
        headers: headers,
      ),
    );
    final accepted = response['response'];
    if (accepted is Map && mounted) {
      setState(() {
        _responses[statementId] = {
          'stance': accepted['stance'].toString(),
          'last_intent_id': accepted['last_intent_id'].toString(),
        };
      });
    }
    await _load();
  }

  Future<void> _withdraw(String statementId) async {
    final current = _responses[statementId];
    final supersedesIntentId = current?['last_intent_id'];
    if (supersedesIntentId == null || supersedesIntentId.isEmpty) return;
    final createdAt = DateTime.now().toUtc();
    final unsigned = DeliberationIntentPayload.withdrawVote(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: widget.host.url,
      boardId: widget.projection.hostedBoardId,
      deliberationId: widget.deliberationId,
      statementId: statementId,
      supersedesIntentId: supersedesIntentId,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    await _signedRequest(
      method: 'DELETE',
      path: '$_basePath/statements/${Uri.encodeComponent(statementId)}/vote',
      unsigned: unsigned,
      send: (client, payload, headers) => client.withdrawDeliberationVote(
        widget.projection.hostedBoardId,
        widget.deliberationId,
        statementId,
        payload,
        headers: headers,
      ),
    );
    if (mounted) setState(() => _responses.remove(statementId));
    await _load();
  }

  Future<void> _loadOwnResponses() async {
    final createdAt = DateTime.now().toUtc();
    final unsigned = DeliberationIntentPayload.readResponses(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: widget.host.url,
      boardId: widget.projection.hostedBoardId,
      deliberationId: widget.deliberationId,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    final result = await _signedRequest(
      method: 'POST',
      path: '$_basePath/responses/mine',
      unsigned: unsigned,
      send: (client, payload, headers) => client.fetchOwnDeliberationResponses(
        widget.projection.hostedBoardId,
        widget.deliberationId,
        payload,
        headers: headers,
      ),
    );
    final values = result['responses'];
    if (values is Map && mounted) {
      setState(() {
        _responses
          ..clear()
          ..addAll(
            values.map(
              (key, value) => MapEntry(
                key.toString(),
                Map<String, String>.from(
                  (value as Map).map(
                    (field, fieldValue) =>
                        MapEntry(field.toString(), fieldValue.toString()),
                  ),
                ),
              ),
            ),
          );
      });
    }
  }

  Future<void> _submitStatement() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.uiCopy(zh: '提出陳述', en: 'Add a statement')),
        content: TextField(
          key: const Key('deliberation_statement_field'),
          controller: controller,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.uiCopy(zh: '送出', en: 'Submit')),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    if (accepted != true || text.isEmpty) return;
    final createdAt = DateTime.now().toUtc();
    final unsigned = DeliberationIntentPayload.statement(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: widget.host.url,
      boardId: widget.projection.hostedBoardId,
      deliberationId: widget.deliberationId,
      text: text,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    await _signedRequest(
      method: 'POST',
      path: '$_basePath/statements',
      unsigned: unsigned,
      send: (client, payload, headers) => client.submitDeliberationStatement(
        widget.projection.hostedBoardId,
        widget.deliberationId,
        payload,
        headers: headers,
      ),
    );
    await _load();
  }

  Future<Map<String, dynamic>> _signedRequest({
    required String method,
    required String path,
    required Map<String, Object?> unsigned,
    required Future<Map<String, dynamic>> Function(
      ForumHostClient,
      Map<String, Object?>,
      Map<String, String>,
    )
    send,
    String capabilityAction = 'post',
  }) async {
    HardwareAuthenticationSession? session;
    final client = ForumHostClient(baseUrl: widget.host.url);
    try {
      final reason = context.uiCopy(
        zh: '請驗證裝置持有人，以送出你的立場。',
        en: 'Authenticate to submit your position.',
      );
      session = await HardwareAuthenticationSession.begin(
        localizedReason: reason,
      );
      if (session == null &&
          !await LocalDeviceUserPresenceVerifier().verify(reason: reason)) {
        throw StateError('device_auth_cancelled');
      }
      final signer = DidSignerImpl(reuseAuthenticationContext: session != null);
      final policy = widget.projection.accessPolicy[capabilityAction];
      final requirement = policy is Map ? policy['requirement'] : null;
      Map<String, String> headers = const {};
      if (requirement != null &&
          requirement != 'public' &&
          requirement != 'posting_policy' &&
          requirement != 'board_moderator') {
        final access = BoardAccessPresentationService(
          walletRepository: DriftWalletRepository(widget.db),
          didSigner: signer,
        );
        final capability = await access.authorize(
          forumHost: Uri.parse(widget.host.url),
          boardId: widget.projection.hostedBoardId,
          action: capabilityAction,
          reuseAuthenticationContext: session != null,
        );
        headers = await access.proofHeaders(
          capability: capability,
          method: method,
          requestUri: Uri.parse(widget.host.url).resolve(path),
          scope: capabilityAction,
          reuseAuthenticationContext: session != null,
        );
      }
      final signature = await signer.sign(
        utf8.encode(forumHostCanonicalJson(unsigned)),
      );
      return await send(client, {
        ...unsigned,
        'signature': signature.hex,
      }, headers);
    } finally {
      await session?.close();
      client.close();
    }
  }

  Future<Map<String, String>> _accessHeaders({
    required String action,
    required String method,
    required String path,
  }) async {
    final policy = widget.projection.accessPolicy[action];
    final requirement = policy is Map ? policy['requirement'] : null;
    if (requirement == null ||
        requirement == 'public' ||
        requirement == 'posting_policy' ||
        requirement == 'board_moderator') {
      return const {};
    }
    final access = BoardAccessPresentationService(
      walletRepository: DriftWalletRepository(widget.db),
      didSigner: DidSignerImpl(),
    );
    final capability = await access.authorize(
      forumHost: Uri.parse(widget.host.url),
      boardId: widget.projection.hostedBoardId,
      action: action,
    );
    return access.proofHeaders(
      capability: capability,
      method: method,
      requestUri: Uri.parse(widget.host.url).resolve(path),
      scope: action,
    );
  }

  Future<void> _exportToLocalAi() async {
    final deliberation = _deliberation;
    if (deliberation == null) return;
    final exportMode = deliberation['export_mode']?.toString();
    if (exportMode == 'no_external_analysis') return;

    var view = 'aggregates';
    if (exportMode == 'pseudonymous_matrix') {
      final matrix = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            context.uiCopy(zh: '提供給本機 AI', en: 'Make available to Local AI'),
          ),
          content: Text(
            context.uiCopy(
              zh: '彙總資料不含個別回應。若選擇回應矩陣，需通過本板的分析權限，參與者只會以這次匯出專用的假名呈現。',
              en: 'Aggregates contain no individual rows. A response matrix requires this board’s analysis permission and uses pseudonyms unique to this export.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.uiCopy(zh: '僅彙總', en: 'Aggregates')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.uiCopy(zh: '回應矩陣', en: 'Response matrix')),
            ),
          ],
        ),
      );
      if (matrix == null) return;
      if (matrix) view = 'pseudonymous_matrix';
    }

    final createdAt = DateTime.now().toUtc();
    final unsigned = DeliberationIntentPayload.export(
      intentId: const Uuid().v4(),
      authorDid: widget.localDid,
      targetForumHost: widget.host.url,
      boardId: widget.projection.hostedBoardId,
      deliberationId: widget.deliberationId,
      view: view,
      createdAt: createdAt,
      expiresAt: createdAt.add(const Duration(minutes: 5)),
    );
    final result = await _signedRequest(
      method: 'POST',
      path: '$_basePath/exports',
      unsigned: unsigned,
      capabilityAction: view == 'pseudonymous_matrix' ? 'analyze' : 'read',
      send: (client, payload, headers) => client.exportSignedDeliberation(
        widget.projection.hostedBoardId,
        widget.deliberationId,
        payload,
        headers: headers,
      ),
    );
    final export = result['export'];
    if (export is! Map) throw const FormatException('Invalid export response');
    await DeliberationExportCacheService(widget.db).save(
      localBoardId: widget.projection.localBoardId,
      title: deliberation['title']?.toString() ?? '',
      export: Map<String, dynamic>.from(export),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.uiCopy(
            zh: '已提供給本機 AI；快照會在 24 小時內到期。',
            en: 'Available to Local AI; this snapshot expires within 24 hours.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _deliberation == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null && _deliberation == null) {
      return Scaffold(body: Center(child: Text(_error!)));
    }
    final deliberation = _deliberation ?? const <String, dynamic>{};
    final statements = (deliberation['statements'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    final report = Map<String, dynamic>.from(
      deliberation['report'] as Map? ?? const {},
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(deliberation['title']?.toString() ?? ''),
        actions: [
          if (deliberation['export_mode'] != 'no_external_analysis')
            IconButton(
              key: const Key('export_deliberation_to_local_ai'),
              tooltip: context.uiCopy(
                zh: '提供給本機 AI',
                en: 'Make available to Local AI',
              ),
              onPressed: _exportToLocalAi,
              icon: const Icon(Icons.smart_toy_outlined),
            ),
          IconButton(
            key: const Key('load_own_deliberation_responses'),
            tooltip: context.uiCopy(zh: '同步我的回應', en: 'Sync my responses'),
            onPressed: _loadOwnResponses,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add_deliberation_statement'),
        onPressed: _submitStatement,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(context.uiCopy(zh: '提出陳述', en: 'Add statement')),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final participation = _participation(
            context,
            deliberation,
            statements,
          );
          final results = _results(context, report);
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(child: participation),
                ),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(child: results),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [participation, results],
          );
        },
      ),
    );
  }

  Widget _participation(
    BuildContext context,
    Map<String, dynamic> deliberation,
    List<Map<String, dynamic>> statements,
  ) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          deliberation['prompt']?.toString() ?? '',
          style: const TextStyle(
            fontFamily: AnsibleDesign.serif,
            fontSize: 20,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _exportDisclosure(context, deliberation['export_mode']?.toString()),
          style: TextStyle(color: Theme.of(context).colorScheme.secondary),
        ),
        const SizedBox(height: 16),
        for (final statement in statements)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statement['text']?.toString() ?? '',
                    style: const TextStyle(fontSize: 17, height: 1.45),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    key: Key('deliberation_vote_${statement['id']}'),
                    segments: [
                      ButtonSegment(
                        value: 'agree',
                        icon: const Icon(Icons.thumb_up_outlined),
                        label: Text(context.uiCopy(zh: '同意', en: 'Agree')),
                      ),
                      ButtonSegment(
                        value: 'disagree',
                        icon: const Icon(Icons.thumb_down_outlined),
                        label: Text(context.uiCopy(zh: '不同意', en: 'Disagree')),
                      ),
                      ButtonSegment(
                        value: 'pass',
                        icon: const Icon(Icons.skip_next_outlined),
                        label: Text(context.uiCopy(zh: '略過', en: 'Pass')),
                      ),
                    ],
                    selected: {
                      if (_responses[statement['id']]?['stance']
                          case final value?)
                        value,
                    },
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) {
                        _vote(statement['id'].toString(), selection.first);
                      }
                    },
                  ),
                  if (_responses[statement['id']] != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _withdraw(statement['id'].toString()),
                        icon: const Icon(Icons.undo),
                        label: Text(
                          context.uiCopy(zh: '撤回回應', en: 'Withdraw response'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _results(BuildContext context, Map<String, dynamic> report) {
    final consensus = (report['consensus'] as List? ?? const [])
        .whereType<Map>()
        .take(5)
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.uiCopy(zh: '目前結果', en: 'Current results'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.uiCopy(
              zh: '${report['participant_count'] ?? 0} 位參與者 · ${report['response_count'] ?? 0} 次回應',
              en: '${report['participant_count'] ?? 0} participants · ${report['response_count'] ?? 0} responses',
            ),
          ),
          const SizedBox(height: 12),
          for (final item in consensus)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.handshake_outlined),
              title: Text(item['text']?.toString() ?? ''),
              subtitle: Text(
                item['agree_ratio'] is num
                    ? '${((item['agree_ratio'] as num) * 100).round()}% ${context.uiCopy(zh: '同意', en: 'agree')}'
                    : context.uiCopy(zh: '樣本不足', en: 'Not enough responses'),
              ),
            ),
          const Divider(),
          Text(
            report['cluster_status'] == 'aggregate_only'
                ? context.uiCopy(
                    zh: '目前版本提供透明彙總；穩定意見群組分析尚未啟用。',
                    en: 'This version provides transparent aggregates; stable opinion clusters are not enabled yet.',
                  )
                : context.uiCopy(
                    zh: '參與人數尚不足以產生意見群組。',
                    en: 'There are not enough participants to form opinion groups.',
                  ),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _exportDisclosure(BuildContext context, String? mode) {
    return switch (mode) {
      'pseudonymous_matrix' => context.uiCopy(
        zh: '符合本看板分析權限的使用者，可將去識別化回應矩陣提供給本機 AI。',
        en: 'Authorized analysts may make a pseudonymous response matrix available to Local AI.',
      ),
      'no_external_analysis' => context.uiCopy(
        zh: '本討論不提供外部 AI 分析資料。',
        en: 'This deliberation does not provide data for external AI analysis.',
      ),
      _ => context.uiCopy(
        zh: '本討論僅提供彙總結果給外部分析。',
        en: 'Only aggregate results are available for external analysis.',
      ),
    };
  }
}
