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
import '../theme/elix_screen_style.dart';

typedef DeliberationDetailLoader = Future<Map<String, dynamic>> Function();

ThemeData deliberationThemeData({
  required ThemeData base,
  required ElixScreenStyle screenStyle,
  required Brightness systemBrightness,
}) {
  final dark =
      screenStyle == ElixScreenStyle.ink ||
      (screenStyle == ElixScreenStyle.system &&
          systemBrightness == Brightness.dark);
  final brightness = dark ? Brightness.dark : Brightness.light;
  final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
  final surface = dark ? AnsibleDesign.darkPaperDeep : AnsibleDesign.paperDeep;
  final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
  final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
  final accent = dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: background,
        secondary: muted,
        onSecondary: background,
        surface: background,
        onSurface: foreground,
      );
  return base.copyWith(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    cardColor: surface,
    dividerColor: dark ? AnsibleDesign.darkRule : AnsibleDesign.rule,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: background,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: accent,
      foregroundColor: background,
    ),
  );
}

class DeliberationsScreen extends StatefulWidget {
  const DeliberationsScreen({
    super.key,
    required this.db,
    required this.board,
    required this.localDid,
    this.screenStyle = ElixScreenStyle.paper,
    this.openCreateOnLoad = false,
  });

  final AppDatabase db;
  final Board board;
  final String localDid;
  final ElixScreenStyle screenStyle;
  final bool openCreateOnLoad;

  @override
  State<DeliberationsScreen> createState() => _DeliberationsScreenState();
}

class _DeliberationsScreenState extends State<DeliberationsScreen> {
  HostedBoardProjection? _projection;
  RemoteNode? _host;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  bool _didAutoOpenCreate = false;
  BuildContext? _routeContext;

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
      context: _routeContext ?? context,
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
    final theme = deliberationThemeData(
      base: Theme.of(context),
      screenStyle: widget.screenStyle,
      systemBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    return ElixScreenStyleScope(
      style: widget.screenStyle,
      child: Theme(
        data: theme,
        child: Builder(
          builder: (routeContext) {
            _routeContext = routeContext;
            return _buildThemed(routeContext);
          },
        ),
      ),
    );
  }

  Widget _buildThemed(BuildContext context) {
    if (widget.openCreateOnLoad &&
        !_didAutoOpenCreate &&
        !_loading &&
        _projection != null) {
      _didAutoOpenCreate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _create();
      });
    }
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
                            screenStyle: widget.screenStyle,
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
    this.screenStyle = ElixScreenStyle.paper,
    this.detailLoader,
  });

  final AppDatabase db;
  final HostedBoardProjection projection;
  final RemoteNode host;
  final String localDid;
  final String deliberationId;
  final ElixScreenStyle screenStyle;
  final DeliberationDetailLoader? detailLoader;

  @override
  State<DeliberationDetailScreen> createState() =>
      _DeliberationDetailScreenState();
}

class _DeliberationDetailScreenState extends State<DeliberationDetailScreen> {
  Map<String, dynamic>? _deliberation;
  final Map<String, Map<String, String>> _responses = {};
  bool _loading = true;
  bool _submittingVote = false;
  int _statementIndex = 0;
  String? _error;
  BuildContext? _routeContext;

  String get _basePath =>
      '/api/v1/forum-host/boards/${Uri.encodeComponent(widget.projection.hostedBoardId)}/deliberations/${Uri.encodeComponent(widget.deliberationId)}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    ForumHostClient? client;
    try {
      final body = widget.detailLoader != null
          ? await widget.detailLoader!()
          : await () async {
              client = ForumHostClient(baseUrl: widget.host.url);
              final headers = await _accessHeaders(
                action: 'read',
                method: 'GET',
                path: _basePath,
              );
              return client!.fetchDeliberation(
                widget.projection.hostedBoardId,
                widget.deliberationId,
                headers: headers,
              );
            }();
      if (!mounted) return;
      final deliberation = Map<String, dynamic>.from(
        body['deliberation'] as Map? ?? const {},
      );
      final projectedResponses = <String, Map<String, String>>{};
      for (final raw in deliberation['statements'] as List? ?? const []) {
        if (raw is! Map) continue;
        final statementId = raw['id']?.toString();
        final response = raw['viewer_response'];
        if (statementId == null || response is! Map) continue;
        final stance = response['stance']?.toString();
        final intentId = response['last_intent_id']?.toString();
        if (stance == null || stance.isEmpty) continue;
        projectedResponses[statementId] = {
          'stance': stance,
          if (intentId != null && intentId.isNotEmpty)
            'last_intent_id': intentId,
        };
      }
      setState(() {
        _deliberation = deliberation;
        _responses.addAll(projectedResponses);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      client?.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _vote(String statementId, String stance) async {
    if (_submittingVote) return;
    if (mounted) setState(() => _submittingVote = true);
    final current = _responses[statementId];
    try {
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
      if (mounted) _advanceToNextUnanswered(statementId);
    } finally {
      if (mounted) setState(() => _submittingVote = false);
    }
  }

  void _advanceToNextUnanswered(String currentStatementId) {
    final statements = _statementMaps();
    if (statements.isEmpty) return;
    final currentIndex = statements.indexWhere(
      (statement) => statement['id']?.toString() == currentStatementId,
    );
    for (var offset = 1; offset <= statements.length; offset++) {
      final candidate = (currentIndex + offset) % statements.length;
      final id = statements[candidate]['id']?.toString();
      if (id != null && !_responses.containsKey(id)) {
        setState(() => _statementIndex = candidate);
        return;
      }
    }
    setState(() {
      _statementIndex = currentIndex < 0 ? 0 : currentIndex;
    });
  }

  List<Map<String, dynamic>> _statementMaps() {
    return (_deliberation?['statements'] as List? ?? const [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
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
      context: _routeContext ?? context,
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
        context: _routeContext ?? context,
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
    final theme = deliberationThemeData(
      base: Theme.of(context),
      screenStyle: widget.screenStyle,
      systemBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    return ElixScreenStyleScope(
      style: widget.screenStyle,
      child: Theme(
        data: theme,
        child: Builder(
          builder: (routeContext) {
            _routeContext = routeContext;
            return _buildThemed(routeContext);
          },
        ),
      ),
    );
  }

  Widget _buildThemed(BuildContext context) {
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
          final results = _results(context, deliberation, report);
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark
        ? AnsibleDesign.darkPaperDeep
        : AnsibleDesign.paperDeep;
    final surface = dark
        ? AnsibleDesign.darkPaperWhite
        : AnsibleDesign.paperWhite;
    final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final faint = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final accent = dark ? AnsibleDesign.darkLavender : AnsibleDesign.lavender;
    final safeIndex = statements.isEmpty
        ? 0
        : _statementIndex.clamp(0, statements.length - 1);
    final statement = statements.isEmpty ? null : statements[safeIndex];
    final statementId = statement?['id']?.toString();
    final selected = statementId == null
        ? null
        : _responses[statementId]?['stance'];
    final answered = statements
        .where((item) => _responses.containsKey(item['id']?.toString()))
        .length;

    return Container(
      key: const Key('deliberation_opinion_map'),
      color: background,
      child: CustomPaint(
        painter: _DeliberationDotPainter(
          color: foreground.withValues(alpha: dark ? 0.055 : 0.045),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hub_outlined, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          context.uiCopy(zh: '意見地圖', en: 'OPINION MAP'),
                          style: TextStyle(
                            color: dark
                                ? AnsibleDesign.darkPaper
                                : Colors.white,
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: context.uiCopy(
                      zh: '上一則陳述',
                      en: 'Previous statement',
                    ),
                    onPressed: statements.length < 2
                        ? null
                        : () => setState(
                            () => _statementIndex =
                                (safeIndex - 1 + statements.length) %
                                statements.length,
                          ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: context.uiCopy(zh: '下一則陳述', en: 'Next statement'),
                    onPressed: statements.length < 2
                        ? null
                        : () => setState(
                            () => _statementIndex =
                                (safeIndex + 1) % statements.length,
                          ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (statements.isNotEmpty)
                Row(
                  key: const Key('deliberation_progress'),
                  children: [
                    for (final item in statements) ...[
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 3,
                          decoration: BoxDecoration(
                            color:
                                _responses.containsKey(item['id']?.toString())
                                ? accent
                                : rule,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (item != statements.last) const SizedBox(width: 5),
                    ],
                    const SizedBox(width: 10),
                    Text(
                      '$answered / ${statements.length}',
                      style: TextStyle(
                        color: faint,
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              if ((deliberation['prompt']?.toString().trim() ?? '').isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 14),
                      title: Text(
                        context.uiCopy(zh: '主題背景', en: 'TOPIC CONTEXT'),
                        style: TextStyle(
                          color: faint,
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 10.5,
                          letterSpacing: 1.1,
                        ),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            deliberation['prompt']?.toString() ?? '',
                            style: TextStyle(
                              color: muted,
                              fontFamily: AnsibleDesign.serif,
                              fontSize: 15.5,
                              height: 1.65,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              if (statement == null)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: rule),
                  ),
                  child: Text(
                    context.uiCopy(
                      zh: '目前還沒有人提出陳述。',
                      en: 'No statements have been proposed yet.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                )
              else
                _statementStack(
                  context: context,
                  deliberation: deliberation,
                  statement: statement,
                  statementIndex: safeIndex,
                  statementCount: statements.length,
                  selected: selected,
                  surface: surface,
                  foreground: foreground,
                  muted: muted,
                  faint: faint,
                  rule: rule,
                  accent: accent,
                  dark: dark,
                ),
              const SizedBox(height: 14),
              Text(
                _exportDisclosure(
                  context,
                  deliberation['export_mode']?.toString(),
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: faint,
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10.5,
                  height: 1.45,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statementStack({
    required BuildContext context,
    required Map<String, dynamic> deliberation,
    required Map<String, dynamic> statement,
    required int statementIndex,
    required int statementCount,
    required String? selected,
    required Color surface,
    required Color foreground,
    required Color muted,
    required Color faint,
    required Color rule,
    required Color accent,
    required bool dark,
  }) {
    final statementId = statement['id'].toString();
    return Column(
      children: [
        Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            if (statementCount > 2)
              Positioned(
                top: 20,
                left: 22,
                right: 22,
                bottom: -20,
                child: _ghostCard(surface, rule, 0.35),
              ),
            if (statementCount > 1)
              Positioned(
                top: 10,
                left: 11,
                right: 11,
                bottom: -10,
                child: _ghostCard(surface, rule, 0.62),
              ),
            Container(
              key: const Key('deliberation_statement_card'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AnsibleDesign.cardRadius),
                border: Border.all(color: rule, width: AnsibleDesign.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deliberation['title']?.toString() ?? '',
                    style: TextStyle(
                      color: faint,
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    statement['text']?.toString() ?? '',
                    style: TextStyle(
                      color: foreground,
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 21,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.uiCopy(
                      zh: '陳述 #${statementIndex + 1} · 來自其他參與者',
                      en: 'Statement #${statementIndex + 1} · From another participant',
                    ),
                    style: TextStyle(
                      color: faint,
                      fontFamily: AnsibleDesign.sans,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 34),
        Row(
          key: Key('deliberation_vote_$statementId'),
          children: [
            Expanded(
              child: _stanceButton(
                context: context,
                stance: 'disagree',
                selected: selected == 'disagree',
                icon: Icons.thumb_down_outlined,
                label: context.uiCopy(zh: '不同意', en: 'Disagree'),
                color: dark ? AnsibleDesign.darkEmber : const Color(0xFFC0475C),
                surface: surface,
                rule: rule,
                statementId: statementId,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _stanceButton(
                context: context,
                stance: 'pass',
                selected: selected == 'pass',
                icon: Icons.skip_next_outlined,
                label: context.uiCopy(zh: '略過', en: 'Pass'),
                color: muted,
                surface: surface,
                rule: rule,
                statementId: statementId,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _stanceButton(
                context: context,
                stance: 'agree',
                selected: selected == 'agree',
                icon: Icons.thumb_up_outlined,
                label: context.uiCopy(zh: '同意', en: 'Agree'),
                color: accent,
                surface: surface,
                rule: rule,
                statementId: statementId,
              ),
            ),
          ],
        ),
        if (selected != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _submittingVote ? null : () => _withdraw(statementId),
              icon: const Icon(Icons.undo, size: 17),
              label: Text(
                context.uiCopy(zh: '撤回這次回應', en: 'Withdraw this response'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _ghostCard(Color surface, Color rule, double opacity) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: rule.withValues(alpha: opacity)),
      ),
    );
  }

  Widget _stanceButton({
    required BuildContext context,
    required String stance,
    required bool selected,
    required IconData icon,
    required String label,
    required Color color,
    required Color surface,
    required Color rule,
    required String statementId,
  }) {
    return OutlinedButton(
      key: Key('deliberation_stance_${statementId}_$stance'),
      onPressed: _submittingVote ? null : () => _vote(statementId, stance),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: selected ? color.withValues(alpha: 0.14) : surface,
        side: BorderSide(color: selected ? color : rule, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(
    BuildContext context,
    Map<String, dynamic> deliberation,
    Map<String, dynamic> report,
  ) {
    final consensus = (report['consensus'] as List? ?? const [])
        .whereType<Map>()
        .take(5)
        .toList();
    final disagreement = (report['disagreement'] as List? ?? const [])
        .whereType<Map>()
        .take(3)
        .toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark
        ? AnsibleDesign.darkPaperWhite
        : AnsibleDesign.paperWhite;
    final foreground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final faint = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final accent = dark ? AnsibleDesign.darkLavender : AnsibleDesign.lavender;
    final highlight = dark
        ? AnsibleDesign.darkHighlight
        : AnsibleDesign.highlight;
    final participantCount = report['participant_count'] ?? 0;
    final responseCount = report['response_count'] ?? 0;
    final statementCount = report['statement_count'] ?? 0;
    return Container(
      key: const Key('deliberation_results'),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 96),
      color: dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.uiCopy(
              zh: 'OPINION MAP · $statementCount 則陳述',
              en: 'OPINION MAP · $statementCount STATEMENTS',
            ),
            style: TextStyle(
              color: dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss,
              fontFamily: AnsibleDesign.mono,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            deliberation['title']?.toString() ?? '',
            style: TextStyle(
              color: foreground,
              fontFamily: AnsibleDesign.serif,
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _resultStat(
                '$participantCount',
                context.uiCopy(zh: '位參與者', en: 'participants'),
                foreground,
                muted,
              ),
              _resultStat(
                '$responseCount',
                context.uiCopy(zh: '次回應', en: 'responses'),
                foreground,
                muted,
              ),
              _resultStat(
                '$statementCount',
                context.uiCopy(zh: '則陳述', en: 'statements'),
                foreground,
                muted,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 126),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: rule),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bubble_chart_outlined, color: faint, size: 34),
                const SizedBox(height: 8),
                Text(
                  report['cluster_status'] == 'aggregate_only'
                      ? context.uiCopy(
                          zh: '目前先提供可驗證的陳述彙總；意見群組分析尚未啟用。',
                          en: 'Verified statement aggregates are available; opinion-group analysis is not enabled yet.',
                        )
                      : context.uiCopy(
                          zh: '參與人數尚不足以產生意見群組。',
                          en: 'There are not enough participants to form opinion groups.',
                        ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12.5, height: 1.5),
                ),
              ],
            ),
          ),
          if (consensus.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('deliberation_consensus_card'),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: highlight.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: highlight, style: BorderStyle.solid),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.uiCopy(
                      zh: '跨群組共識 · CONSENSUS',
                      en: 'SHARED GROUND · CONSENSUS',
                    ),
                    style: TextStyle(
                      color: accent,
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    consensus.first['text']?.toString() ?? '',
                    style: TextStyle(
                      color: foreground,
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 14.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (disagreement.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              context.uiCopy(zh: '最具分歧的陳述', en: 'Most divisive statements'),
              style: TextStyle(
                color: foreground,
                fontFamily: AnsibleDesign.sans,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final item in disagreement)
              _aggregateResultCard(
                context: context,
                item: Map<String, dynamic>.from(item),
                surface: surface,
                foreground: foreground,
                faint: faint,
                rule: rule,
                accent: accent,
                dark: dark,
              ),
          ],
        ],
      ),
    );
  }

  Widget _resultStat(
    String value,
    String label,
    Color foreground,
    Color muted,
  ) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: ' $label',
            style: TextStyle(color: muted),
          ),
        ],
      ),
      style: const TextStyle(fontFamily: AnsibleDesign.sans, fontSize: 12.5),
    );
  }

  Widget _aggregateResultCard({
    required BuildContext context,
    required Map<String, dynamic> item,
    required Color surface,
    required Color foreground,
    required Color faint,
    required Color rule,
    required Color accent,
    required bool dark,
  }) {
    final agree = int.tryParse(item['agree']?.toString() ?? '') ?? 0;
    final disagree = int.tryParse(item['disagree']?.toString() ?? '') ?? 0;
    final pass = int.tryParse(item['pass']?.toString() ?? '') ?? 0;
    final total = agree + disagree + pass;
    final agreePct = total == 0 ? 0 : (agree * 100 / total).round();
    final passPct = total == 0 ? 0 : (pass * 100 / total).round();
    final disagreePct = total == 0 ? 0 : 100 - agreePct - passPct;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item['text']?.toString() ?? '',
            style: TextStyle(
              color: foreground,
              fontFamily: AnsibleDesign.serif,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (agreePct > 0)
                  Expanded(
                    flex: agreePct,
                    child: Container(height: 6, color: accent),
                  ),
                if (passPct > 0)
                  Expanded(
                    flex: passPct,
                    child: Container(height: 6, color: rule),
                  ),
                if (disagreePct > 0)
                  Expanded(
                    flex: disagreePct,
                    child: Container(
                      height: 6,
                      color: dark
                          ? AnsibleDesign.darkEmber
                          : const Color(0xFFE8778A),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          DefaultTextStyle(
            style: TextStyle(
              color: faint,
              fontFamily: AnsibleDesign.mono,
              fontSize: 10.5,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$agreePct% ${context.uiCopy(zh: '同意', en: 'agree')}'),
                Text('$passPct% ${context.uiCopy(zh: '略過', en: 'pass')}'),
                Text(
                  '$disagreePct% ${context.uiCopy(zh: '不同意', en: 'disagree')}',
                ),
              ],
            ),
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

class _DeliberationDotPainter extends CustomPainter {
  const _DeliberationDotPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 16.0;
    for (var y = 1.0; y < size.height; y += spacing) {
      for (var x = 1.0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DeliberationDotPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
