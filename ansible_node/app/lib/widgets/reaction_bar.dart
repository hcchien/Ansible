import 'dart:async';

import 'package:ansible_domain/ansible_domain.dart';
import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_l10n.dart';
import '../config/app_environment.dart';
import '../services/app_view_timeline_client.dart';
import '../services/ops_dispatch_service.dart';
import 'author_label.dart';
import 'reaction_picker.dart';

/// The same selection, live counts and public attribution on every client.
class ReactionBar extends StatefulWidget {
  const ReactionBar({
    super.key,
    required this.db,
    required this.targetId,
    required this.targetType,
    this.boardId,
    this.localDid,
    this.opsDispatchService,
    this.onFlushPendingOps,
    this.remoteItems = const [],
    this.fallbackCount = 0,
    this.color,
    this.publicThreadId,
  });

  final AppDatabase db;
  final String targetId;
  final TargetType targetType;
  final String? boardId;
  final String? localDid;
  final OpsDispatchService? opsDispatchService;
  final Future<void> Function()? onFlushPendingOps;
  final List<AppViewTimelineItem> remoteItems;
  final int fallbackCount;
  final Color? color;
  final String? publicThreadId;

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  late DriftReactionRepository _repo;
  StreamSubscription<List<Reaction>>? _subscription;
  List<Reaction> _local = [];
  OpsQueueEntry? _latestLocalOp;
  final Map<String, Reaction?> _overrides = {};
  bool _busy = false;
  List<AppViewTimelineItem> _remote = const [];
  static final _requests =
      <String, ({DateTime at, Future<List<AppViewTimelineItem>> result})>{};

  Future<void> _loadRemote() async {
    final id = widget.publicThreadId;
    if (id == null || AppEnvironment.appViewBaseUrl.isEmpty) return;
    try {
      // Do not send a local draft/private content id to the public read model.
      final content = await DriftContentItemRepository(widget.db).getById(id);
      if (content != null &&
          (content.localOnly ||
              content.visibility == ContentVisibility.private ||
              content.status == ContentStatus.draft)) {
        return;
      }
      if (widget.boardId?.isNotEmpty == true) {
        final board = await DriftHostedBoardRepository(
          widget.db,
        ).getProjectionByLocalBoardId(widget.boardId!);
        if (board != null && board.contentVisibility != 'public') return;
      }
      var request = _requests[id];
      if (request == null ||
          DateTime.now().difference(request.at).inSeconds > 10) {
        final result = () async {
          final client = AppViewTimelineClient(
            baseUrl: AppEnvironment.appViewBaseUrl,
          );
          final page = await client.fetchCompleteThread(threadId: id);
          return page.items.where((i) => i.entityType == 'reaction').toList();
        }();
        if (_requests.length > 100) _requests.clear();
        request = (at: DateTime.now(), result: result);
        _requests[id] = request;
      }
      final items = await request.result;
      if (mounted && widget.publicThreadId == id) {
        setState(() => _remote = items);
      }
    } catch (_) {
      _requests.remove(id);
    }
  }

  @override
  void initState() {
    super.initState();
    _listen();
    unawaited(_loadRemote());
  }

  void _listen() {
    final targetId = widget.targetId;
    final targetType = widget.targetType;
    final localDid = widget.localDid;
    final db = widget.db;
    _repo = DriftReactionRepository(db);
    _subscription = _repo.watchByTarget(targetType.name, targetId).listen((
      rows,
    ) async {
      final latest = localDid == null
          ? null
          : await DriftOpsQueueRepository(
              db,
            ).latestReactionForTarget(localDid, targetType.name, targetId);
      if (mounted &&
          widget.db == db &&
          widget.targetId == targetId &&
          widget.targetType == targetType &&
          widget.localDid == localDid) {
        setState(() {
          _local = rows;
          _latestLocalOp = latest;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReactionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.publicThreadId != widget.publicThreadId) {
      _remote = const [];
      unawaited(_loadRemote());
    }
    if (oldWidget.localDid != widget.localDid ||
        oldWidget.db != widget.db ||
        oldWidget.targetId != widget.targetId ||
        oldWidget.targetType != widget.targetType) {
      _subscription?.cancel();
      _local = [];
      _latestLocalOp = null;
      _overrides.clear();
      _listen();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<Reaction> get _reactions {
    final byDid = <String, Reaction>{};
    final aliases = <String, String>{};
    for (final item in [..._remote, ...widget.remoteItems]) {
      if (item.entityType != 'reaction' ||
          item.payload['targetId'] != widget.targetId ||
          item.payload['targetType'] != widget.targetType.name) {
        continue;
      }
      final type = ReactionType.values
          .where((t) => t.name == item.payload['reactionType'])
          .firstOrNull;
      if (type == null) continue;
      final did = (item.canonicalAuthorDid?.isNotEmpty ?? false)
          ? item.canonicalAuthorDid!
          : item.authorDid;
      aliases[item.authorDid] = did;
      byDid[did] = Reaction(
        id: item.entityId,
        userId: item.authorDid,
        targetType: widget.targetType,
        targetId: widget.targetId,
        reactionType: type,
        createdAt: item.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    for (final r in _local) {
      byDid.putIfAbsent(aliases[r.userId] ?? r.userId, () => r);
    }
    final latest = _latestLocalOp;
    if (latest != null) {
      final did = aliases[latest.authorDid] ?? latest.authorDid;
      final remote = byDid[did];
      if (remote == null || !remote.createdAt.isAfter(latest.createdAt)) {
        final mine = _local
            .where((r) => r.userId == latest.authorDid)
            .firstOrNull;
        if (latest.opType == 'delete' && mine == null) {
          byDid.remove(did);
        } else if (mine != null) {
          byDid[did] = mine;
        }
      }
    }
    for (final entry in _overrides.entries) {
      final did = aliases[entry.key] ?? entry.key;
      if (entry.value == null) {
        byDid.remove(did);
      } else {
        byDid[did] = entry.value!;
      }
    }
    return byDid.values.toList();
  }

  Future<void> _choose() async {
    if (_busy || widget.localDid == null || widget.opsDispatchService == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final mine = _reactions
          .where((r) => r.userId == widget.localDid)
          .firstOrNull;
      final choice = await showReactionPicker(
        context,
        selected: mine?.reactionType,
      );
      if (choice == null || !mounted) return;
      final existing =
          await _repo.getByUserAndTarget(
            widget.localDid!,
            widget.targetType.name,
            widget.targetId,
          ) ??
          mine;
      if (choice.remove && existing == null) return;
      final id = existing?.id ?? const Uuid().v4();
      final op = choice.remove
          ? CrdtOpBuilder.deleteReaction(
              authorDid: widget.localDid!,
              entityId: id,
              targetType: widget.targetType.name,
              targetId: widget.targetId,
              boardId: widget.boardId,
            )
          : existing != null
          ? CrdtOpBuilder.updateReaction(
              authorDid: widget.localDid!,
              entityId: id,
              targetType: widget.targetType.name,
              targetId: widget.targetId,
              reactionType: choice.type!.name,
              boardId: widget.boardId,
            )
          : CrdtOpBuilder.createReaction(
              authorDid: widget.localDid!,
              entityId: id,
              targetType: widget.targetType.name,
              targetId: widget.targetId,
              reactionType: choice.type!.name,
              boardId: widget.boardId,
            );
      // A cancelled/failed signing ceremony must not change the visible choice.
      await widget.opsDispatchService!.signAndEnqueue(op);
      if (choice.remove) {
        await _repo.delete(id);
        _overrides[widget.localDid!] = null;
      } else {
        final reaction = Reaction(
          id: id,
          userId: widget.localDid!,
          targetType: widget.targetType,
          targetId: widget.targetId,
          reactionType: choice.type!,
          createdAt: existing?.createdAt ?? DateTime.now(),
        );
        await _repo.create(reaction);
        _overrides[widget.localDid!] = reaction;
      }
      if (mounted) setState(() {});
      _requests.remove(widget.publicThreadId);
      await widget.onFlushPendingOps?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.uiCopy(
                zh: '反應尚未同步，請重試',
                en: 'Reaction has not synced. Please retry.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _person(Reaction reaction) {
    final profile = [
      ..._remote,
      ...widget.remoteItems,
    ].where((i) => i.authorDid == reaction.userId).firstOrNull;
    final did = profile?.canonicalAuthorDid ?? reaction.userId;
    return ListTile(
      key: ValueKey('reaction_person_${reaction.userId}'),
      leading: Text(reactionEmoji(reaction.reactionType)),
      title: AuthorLabel(
        did: did,
        displayName: profile?.authorDisplayName,
        handle: profile?.authorHandle,
        resolveProfileBeforeHandle: true,
      ),
      subtitle: Text(
        profile?.authorHandle?.isNotEmpty == true
            ? '@${profile!.authorHandle!.replaceFirst('@', '')}'
            : did,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _showPeople() async {
    await _loadRemote();
    if (!mounted) return;
    final reactions = _reactions;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                context.uiCopy(zh: '誰按了哪些反應', en: 'Who reacted'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (reactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    context.uiCopy(
                      zh: '尚無已載入的反應',
                      en: 'No reactions loaded yet',
                    ),
                  ),
                ),
              for (final type in ReactionType.values)
                if (reactions.any((r) => r.reactionType == type)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      '${reactionEmoji(type)} ${reactions.where((r) => r.reactionType == type).length}',
                    ),
                  ),
                  for (final reaction in reactions.where(
                    (r) => r.reactionType == type,
                  ))
                    _person(reaction),
                ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reactions = _reactions;
    final selected = reactions
        .where((r) => r.userId == widget.localDid)
        .firstOrNull;
    final count = reactions.isEmpty && _overrides.isEmpty
        ? widget.fallbackCount
        : reactions.length;
    final summary = ReactionType.values
        .where((type) => reactions.any((r) => r.reactionType == type))
        .map(reactionEmoji)
        .join('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: context.uiCopy(zh: '選擇反應', en: 'Choose reaction'),
          visualDensity: VisualDensity.compact,
          onPressed:
              _busy ||
                  widget.localDid == null ||
                  widget.opsDispatchService == null
              ? null
              : _choose,
          icon: selected == null
              ? Icon(Icons.favorite_border, size: 19, color: widget.color)
              : Text(
                  reactionEmoji(selected.reactionType),
                  style: TextStyle(fontSize: 20, color: widget.color),
                ),
        ),
        if (count > 0)
          TextButton(
            onPressed: _showPeople,
            style: TextButton.styleFrom(
              foregroundColor: widget.color,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 40),
            ),
            child: Text(
              summary.isEmpty ? '$count' : '$summary $count',
              maxLines: 2,
              style: const TextStyle(fontSize: 12),
              semanticsLabel: context.uiCopy(
                zh: '查看 $count 個反應及使用者',
                en: 'View $count reactions and people',
              ),
            ),
          ),
      ],
    );
  }
}
