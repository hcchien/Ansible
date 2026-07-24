import 'dart:convert';

import 'package:ansible_did/ansible_did.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_l10n.dart';
import '../l10n/user_facing_error.dart';
import '../services/forum_host_client.dart';
import '../services/board_access_presentation_service.dart';
import '../services/private_board_rotation_service.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';
import '../widgets/board_form_dialog.dart';

/// A board this user's DID created on a Forum Host, paired with the host it
/// lives on (board management is per-host; the host is the write target).
class HostedBoardEntry {
  final RemoteNode host;
  final Map<String, dynamic> board;

  const HostedBoardEntry({required this.host, required this.board});

  String get hostedBoardId => board['hosted_board_id'] as String? ?? '';
  String get title => board['title'] as String? ?? hostedBoardId;
  String? get description => board['description'] as String?;
  String get contentVisibility =>
      board['content_visibility'] as String? ?? 'public';

  Map<String, Object?> get postingPolicy =>
      Map<String, Object?>.from(board['posting_policy'] as Map? ?? const {});

  Map<String, Object?> get accessPolicy =>
      Map<String, Object?>.from(board['access_policy'] as Map? ?? const {});

  String? get minPostTier {
    final tier = postingPolicy['min_post_tier'];
    if (tier is String && tier.trim().isNotEmpty) return tier;
    return null;
  }
}

/// "My hosted boards" management screen: lists the boards this DID created
/// on each active Forum Host (authorship is recorded host-side) and lets the
/// creator edit title, description, and posting policy through a signed
/// `update_board` intent. Successful updates refresh the local
/// [HostedBoardProjection] cache and the mirrored local [Board] row.
class HostedBoardsScreen extends StatefulWidget {
  final AppDatabase? db;
  final String did;
  final RemoteNodeRepository remoteNodeRepo;
  final HostedBoardRepository hostedBoardRepo;
  final BoardRepository boardRepo;

  /// Injectable for tests; defaults to a real [ForumHostClient] per host.
  final ForumHostClient Function(String baseUrl)? clientFactory;

  /// Signs canonical intent bytes with the user's DID key; injectable for
  /// tests. Defaults to [DidSignerImpl].
  final Future<String> Function(List<int> message)? signIntent;

  /// Optional create-board entry point shown in the empty state.
  final VoidCallback? onCreateBoard;

  const HostedBoardsScreen({
    super.key,
    required this.did,
    required this.remoteNodeRepo,
    required this.hostedBoardRepo,
    required this.boardRepo,
    this.db,
    this.clientFactory,
    this.signIntent,
    this.onCreateBoard,
  });

  @override
  State<HostedBoardsScreen> createState() => _HostedBoardsScreenState();
}

class _HostedBoardsScreenState extends State<HostedBoardsScreen> {
  static const _uuid = Uuid();

  bool _loading = true;
  bool _loadFailed = false;
  List<HostedBoardEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  ForumHostClient _clientFor(String baseUrl) {
    final factory = widget.clientFactory;
    return factory == null
        ? ForumHostClient(baseUrl: baseUrl)
        : factory(baseUrl);
  }

  Future<String> _sign(List<int> message) {
    final signer = widget.signIntent;
    if (signer != null) return signer(message);
    return DidSignerImpl().sign(message).then((signature) => signature.hex);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final entries = <HostedBoardEntry>[];
    var hostCount = 0;
    var failures = 0;
    try {
      final hosts = (await widget.remoteNodeRepo.list())
          .where((node) => node.isActive)
          .toList();
      hostCount = hosts.length;
      for (final host in hosts) {
        final client = _clientFor(host.url);
        try {
          final boards = await client.listBoardsCreatedBy(widget.did);
          for (final board in boards) {
            final hostedBoardId = board['hosted_board_id'] as String?;
            if (hostedBoardId == null || hostedBoardId.isEmpty) continue;
            entries.add(HostedBoardEntry(host: host, board: board));
          }
        } catch (_) {
          // Per-host best-effort; only an all-hosts failure surfaces below.
          failures += 1;
        } finally {
          client.close();
        }
      }
    } catch (_) {
      failures = hostCount == 0 ? 1 : hostCount;
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
      _loadFailed = hostCount > 0 && failures >= hostCount && entries.isEmpty;
    });
  }

  Future<void> _editBoard(HostedBoardEntry entry) async {
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (context) => BoardFormDialog(
        initialTitle: entry.title,
        initialDescription: entry.description,
        showPostingPolicy: true,
        initialMinPostTier: entry.minPostTier,
      ),
    );
    if (result == null || !mounted) return;

    final title = (result['title'] ?? entry.title).trim();
    // Empty description clears the stored one host-side.
    final description = result['description'] ?? '';
    // Preserve unrelated policy keys (e.g. external_inclusion); only the gate
    // selector is edited here.
    final newPolicy = Map<String, Object?>.from(entry.postingPolicy);
    final newTier = result['minPostTier'];
    if (newTier == null) {
      newPolicy.remove('min_post_tier');
    } else {
      newPolicy['min_post_tier'] = newTier;
    }

    final intentId = _uuid.v4();
    final createdAt = DateTime.now().toUtc();
    final expiresAt = createdAt.add(const Duration(minutes: 5));
    final canonicalPayload = UpdateHostedBoardIntent.canonicalPayload(
      intentId: intentId,
      authorDid: widget.did,
      targetForumHost: entry.host.url,
      boardId: entry.hostedBoardId,
      title: title,
      description: description,
      postingPolicy: newPolicy,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );

    try {
      final signature = await _sign(
        utf8.encode(forumHostCanonicalJson(canonicalPayload)),
      );
      final client = _clientFor(entry.host.url);
      final Map<String, dynamic> updated;
      try {
        updated = await client.updateHostedBoard(
          UpdateHostedBoardIntent(
            intentId: intentId,
            authorDid: widget.did,
            targetForumHost: entry.host.url,
            signature: signature,
            boardId: entry.hostedBoardId,
            title: title,
            description: description,
            postingPolicy: newPolicy,
            createdAt: createdAt,
            expiresAt: expiresAt,
          ),
        );
      } finally {
        client.close();
      }
      await _applyLocalUpdate(entry, updated);
      if (!mounted) return;
      setState(() {
        _entries = [
          for (final existing in _entries)
            if (identical(existing, entry))
              HostedBoardEntry(
                host: entry.host,
                board: {...entry.board, ...updated},
              )
            else
              existing,
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '已更新看板「${updated['title'] ?? title}」',
              en: 'Board "${updated['title'] ?? title}" updated',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    }
  }

  Future<void> _rotatePrivateBoard(HostedBoardEntry entry) async {
    final db = widget.db;
    final projection = await widget.hostedBoardRepo.getProjection(
      entry.host.id,
      entry.hostedBoardId,
    );
    if (db == null || projection == null) return;
    try {
      final epoch = await PrivateBoardRotationService(
        access: BoardAccessPresentationService(
          walletRepository: DriftWalletRepository(db),
        ),
      ).rotate(forumHost: Uri.parse(entry.host.url), board: projection);
      await widget.hostedBoardRepo.upsertProjection(
        projection.copyWith(encryptionEpoch: epoch, encryptionState: 'ready'),
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '私密看板金鑰已輪替至第 $epoch 版',
              en: 'Private-board key rotated to epoch $epoch',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    }
  }

  Future<void> _editAccessPolicy(HostedBoardEntry entry) async {
    var visibility = entry.contentVisibility;
    final issuerController = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.uiCopy(zh: '看板存取政策', en: 'Board access policy')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: visibility,
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: '內容可見性', en: 'Visibility'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'public',
                    child: Text(context.uiCopy(zh: '公開', en: 'Public')),
                  ),
                  DropdownMenuItem(
                    value: 'host_visible',
                    child: Text(context.uiCopy(zh: '會員限定', en: 'Members only')),
                  ),
                  DropdownMenuItem(
                    value: 'end_to_end_encrypted',
                    child: Text(
                      context.uiCopy(zh: '端對端加密', en: 'End-to-end encrypted'),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => visibility = value);
                },
              ),
              if (visibility != 'public') ...[
                const SizedBox(height: 14),
                TextField(
                  controller: issuerController,
                  decoration: InputDecoration(
                    labelText: context.uiCopy(
                      zh: '信任的 Issuer DID',
                      en: 'Trusted issuer DID',
                    ),
                    hintText: 'did:web:issuer.example',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                context.uiCopy(
                  zh: '存取範圍或信任來源的變更會延遲至少 24 小時生效，並保留不可變更的政策歷史。',
                  en: 'Access-scope and trust changes take effect after at least 24 hours and remain in immutable policy history.',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final issuer = issuerController.text.trim();
                if (visibility != 'public' && !issuer.startsWith('did:')) {
                  return;
                }
                Navigator.pop(context, {
                  'visibility': visibility,
                  if (issuer.isNotEmpty) 'issuer': issuer,
                });
              },
              child: Text(context.uiCopy(zh: '排程變更', en: 'Schedule change')),
            ),
          ],
        ),
      ),
    );
    issuerController.dispose();
    if (result == null || !mounted) return;

    final selectedVisibility = result['visibility']!;
    final public = selectedVisibility == 'public';
    final accessPolicy = public
        ? <String, Object?>{
            'version': 1,
            'discovery': 'public',
            'read': {'requirement': 'public'},
            'post': {'requirement': 'posting_policy'},
            'moderate': {'requirement': 'board_moderator'},
            'requirements': <String, Object?>{},
            'capability_ttl_seconds': 300,
            'content_visibility': 'public',
            'federation': 'enabled',
          }
        : <String, Object?>{
            'version': 1,
            'discovery': 'credential_required',
            'read': {'requirement': 'member'},
            'post': {'requirement': 'member'},
            'moderate': {'requirement': 'board_moderator'},
            'requirements': {
              'member': {
                'credential_type': 'PoliticalPartyMembershipCredential',
                'trusted_issuers': [result['issuer']!],
                'claims': [
                  {'path': 'membership', 'op': 'equals', 'value': true},
                ],
                'holder_binding': 'required',
                'status': {'required': true, 'max_age_seconds': 300},
              },
            },
            'capability_ttl_seconds': 300,
            'content_visibility': selectedVisibility,
            'federation': 'disabled',
          };
    final newPolicy = <String, Object?>{
      'access_policy': accessPolicy,
      'content_visibility': selectedVisibility,
      'federation_policy': {'mode': public ? 'enabled' : 'disabled'},
    };

    final client = _clientFor(entry.host.url);
    try {
      final history = await client.getHostedBoardPolicyHistory(
        entry.hostedBoardId,
      );
      if (history.isEmpty || history.first['policy_hash'] is! String) {
        throw const FormatException('Missing current board policy hash');
      }
      final createdAt = DateTime.now().toUtc();
      final effectiveAt = createdAt.add(const Duration(hours: 24, seconds: 10));
      final expiresAt = createdAt.add(const Duration(minutes: 5));
      final intentId = _uuid.v4();
      final previousHash = history.first['policy_hash'] as String;
      final canonical = UpdateHostedBoardPolicyIntent.canonicalPayload(
        intentId: intentId,
        authorDid: widget.did,
        boardId: entry.hostedBoardId,
        previousPolicyHash: previousHash,
        targetForumHost: entry.host.url,
        newPolicy: newPolicy,
        createdAt: createdAt,
        expiresAt: expiresAt,
        effectiveAt: effectiveAt,
      );
      final signature = await _sign(
        utf8.encode(forumHostCanonicalJson(canonical)),
      );
      await client.updateHostedBoardPolicy(
        UpdateHostedBoardPolicyIntent(
          intentId: intentId,
          authorDid: widget.did,
          boardId: entry.hostedBoardId,
          previousPolicyHash: previousHash,
          targetForumHost: entry.host.url,
          newPolicy: newPolicy,
          createdAt: createdAt,
          expiresAt: expiresAt,
          effectiveAt: effectiveAt,
          signature: signature,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.uiCopy(
              zh: '政策變更已排程，將於 24 小時後生效',
              en: 'Policy change scheduled to take effect in 24 hours',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userFacingError(context, error))));
    } finally {
      client.close();
    }
  }

  /// Mirrors an accepted host-side update into the local projection cache and
  /// the local board row, when this device is subscribed to the board.
  Future<void> _applyLocalUpdate(
    HostedBoardEntry entry,
    Map<String, dynamic> updated,
  ) async {
    final now = DateTime.now();
    final title = updated['title'] as String? ?? entry.title;
    final description = updated['description'] as String?;
    final postingPolicy = Map<String, Object?>.from(
      updated['posting_policy'] as Map? ?? entry.postingPolicy,
    );

    final projection = await widget.hostedBoardRepo.getProjection(
      entry.host.id,
      entry.hostedBoardId,
    );
    if (projection == null) return;

    // Not copyWith: a cleared description must overwrite the cached one.
    await widget.hostedBoardRepo.upsertProjection(
      HostedBoardProjection(
        localBoardId: projection.localBoardId,
        forumHostId: projection.forumHostId,
        hostedBoardId: projection.hostedBoardId,
        canonicalBoardUri: projection.canonicalBoardUri,
        remoteSlug: projection.remoteSlug,
        localSlug: projection.localSlug,
        title: title,
        description: description,
        permissions: projection.permissions,
        postingPolicy: postingPolicy,
        accessPolicy: projection.accessPolicy,
        accessPolicyVersion: projection.accessPolicyVersion,
        contentVisibility: projection.contentVisibility,
        encryptionEpoch: projection.encryptionEpoch,
        encryptionState: projection.encryptionState,
        federationPolicy: projection.federationPolicy,
        lastSeenCursor: projection.lastSeenCursor,
        createdAt: projection.createdAt,
        updatedAt: now,
        isDeleted: projection.isDeleted,
      ),
    );

    final localBoard = await widget.boardRepo.getById(projection.localBoardId);
    if (localBoard != null) {
      await widget.boardRepo.update(
        Board(
          id: localBoard.id,
          slug: localBoard.slug,
          title: title,
          description: description,
          createdAt: localBoard.createdAt,
          updatedAt: now,
          isDeleted: localBoard.isDeleted,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '我主持的看板', en: 'BOARDS I HOST'),
      leadingLabel: context.uiCopy(zh: '← 返回', en: '← Back'),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.uiCopy(
                zh: '無法載入你主持的看板，請檢查網路後再試一次。',
                en:
                    'Could not load the boards you host. Check your network '
                    'and try again.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: Text(context.uiCopy(zh: '重試', en: 'Retry')),
            ),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return _buildEmptyState(context);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        itemCount: _entries.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          thickness: 0.5,
          color: AnsibleDesign.ruleSoft,
        ),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(entry.title),
            subtitle: Text(
              [
                if (entry.description?.isNotEmpty ?? false) entry.description!,
                entry.host.name,
                if (entry.minPostTier != null)
                  context.uiCopy(zh: '僅限真人驗證發文', en: 'Verified humans only'),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rotate') {
                  _rotatePrivateBoard(entry);
                } else if (value == 'policy') {
                  _editAccessPolicy(entry);
                } else {
                  _editBoard(entry);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.uiCopy(zh: '編輯看板', en: 'Edit board')),
                ),
                PopupMenuItem(
                  value: 'policy',
                  child: Text(
                    context.uiCopy(
                      zh: '存取與隱私政策',
                      en: 'Access & privacy policy',
                    ),
                  ),
                ),
                if (entry.contentVisibility == 'end_to_end_encrypted' &&
                    widget.db != null)
                  PopupMenuItem(
                    value: 'rotate',
                    child: Text(
                      context.uiCopy(
                        zh: '輪替私密看板金鑰',
                        en: 'Rotate private-board key',
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () => _editBoard(entry),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.dashboard_customize_outlined,
              size: 40,
              color: AnsibleDesign.inkFaint,
            ),
            const SizedBox(height: 16),
            Text(
              context.uiCopy(
                zh: '你還沒有主持任何看板',
                en: 'You are not hosting any boards yet',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              context.uiCopy(
                zh: '建立看板後，你可以在這裡編輯標題、描述與發文資格。',
                en:
                    'Create a board and manage its title, description, and '
                    'posting rules here.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AnsibleDesign.inkMuted,
              ),
            ),
            if (widget.onCreateBoard != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onCreateBoard!();
                },
                icon: const Icon(Icons.add),
                label: Text(context.uiCopy(zh: '建立看板', en: 'Create board')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
