import 'dart:async';

import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/posting_gate.dart';
import '../theme/ansible_design.dart';

/// A board item has a dedicated creation path.  A poll is intentionally not a
/// discussion with an optional toggle: it has its own entry point and editor.
enum ThreadComposerType { discussion, poll }

/// Full-screen composer for a new forum discussion, styled to match the app's
/// design system (mirrors [NoteEditorScreen]'s chrome). Replaces the old
/// Material `AlertDialog`. Pops
/// `{boardId, title, content, crossPostTargetIds, publicationDeferred}` on
/// submit, or null on cancel — the caller consumes the map and dispatches the
/// ops/publication.
class ThreadComposerScreen extends StatefulWidget {
  const ThreadComposerScreen({
    super.key,
    required this.boards,
    this.initialBoardId,
    this.authorDid,
    this.db,
    this.type = ThreadComposerType.discussion,
  });

  final List<Board> boards;
  final String? initialBoardId;

  /// Shown in the footer for parity with the note editor. Optional.
  final String? authorDid;

  /// When provided, the composer pre-checks the selected board's posting gate
  /// and subscription permissions. A blocked post is still saved locally but
  /// publication is deferred until a later explicit sync can satisfy policy.
  /// The relay stays the source of truth for enforcement.
  final AppDatabase? db;

  final ThreadComposerType type;

  @override
  State<ThreadComposerScreen> createState() => _ThreadComposerScreenState();
}

/// A cross-post candidate: another subscribed, writable hosted board the
/// user clears the posting gate for.
class _CrossPostTarget {
  final String subscriptionId;
  final String boardTitle;

  const _CrossPostTarget({
    required this.subscriptionId,
    required this.boardTitle,
  });
}

class _ThreadComposerScreenState extends State<ThreadComposerScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  String? _selectedBoardId;
  String? _error;
  bool get _isPoll => widget.type == ThreadComposerType.poll;
  int? _pollDurationDays = 3;

  /// True when the selected board requires a tier the local user lacks.
  /// UX pre-validation only — the relay re-checks at intent acceptance.
  bool _postingBlocked = false;
  bool _writeEnabled = true;

  bool get _publicationDeferred => _postingBlocked || !_writeEnabled;

  /// Other subscribed writable boards the user can also publish to
  /// (excluding the primary board and any board whose gate the user fails).
  List<_CrossPostTarget> _crossPostTargets = const [];
  final Set<String> _selectedCrossPostIds = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedBoardId =
        widget.initialBoardId ??
        (widget.boards.isNotEmpty ? widget.boards.first.id : null);
    _titleController.addListener(() => setState(() {}));
    _contentController.addListener(() => setState(() {}));
    unawaited(_loadBoardPolicy());
  }

  /// Computes the selected board's posting-gate pre-check and the list of
  /// cross-post candidates. Skips silently when no [ThreadComposerScreen.db]
  /// was provided (e.g. previews); the gate stays discoverable before
  /// posting (constitution Base Rule 6) whenever we can check it.
  Future<void> _loadBoardPolicy() async {
    final db = widget.db;
    final boardId = _selectedBoardId;
    if (db == null || boardId == null) return;
    final hostedRepo = DriftHostedBoardRepository(db);
    final boardRepo = DriftBoardRepository(db);
    final did = widget.authorDid;
    final tier = (did == null || did.isEmpty)
        ? PostingGate.basicTier
        : await DriftDidReputationRepository(db).tierFor(did);
    final projection = await hostedRepo.getProjectionByLocalBoardId(boardId);
    final subscriptions = await hostedRepo.listSubscriptions();
    BoardSubscription? primarySubscription;
    for (final subscription in subscriptions) {
      if (subscription.localBoardId == boardId) {
        primarySubscription = subscription;
        break;
      }
    }
    final blocked =
        projection != null &&
        !PostingGate.satisfies(tier, projection.minPostTier);
    // A projection without a subscription is normally a locally hosted board
    // owned by this device. Only an explicit read-only subscription disables
    // immediate publication.
    final writeEnabled = primarySubscription?.writeEnabled ?? true;

    final targets = <_CrossPostTarget>[];
    for (final subscription in subscriptions) {
      if (!subscription.writeEnabled) continue;
      if (subscription.localBoardId == boardId) continue;
      final targetProjection = await hostedRepo.getProjectionByLocalBoardId(
        subscription.localBoardId,
      );
      // Respect each target's own posting gate: never offer a board the
      // user cannot post to.
      if (targetProjection != null &&
          !PostingGate.satisfies(tier, targetProjection.minPostTier)) {
        continue;
      }
      final board = await boardRepo.getById(subscription.localBoardId);
      if (board == null || board.isDeleted) continue;
      targets.add(
        _CrossPostTarget(
          subscriptionId: subscription.subscriptionId,
          boardTitle: board.title,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _postingBlocked = blocked;
      _writeEnabled = writeEnabled;
      _crossPostTargets = targets;
      _selectedCrossPostIds.removeWhere(
        (id) => !targets.any((target) => target.subscriptionId == id),
      );
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    for (final controller in _pollOptionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addPollOption() {
    if (_pollOptionControllers.length >= 12) return;
    setState(() => _pollOptionControllers.add(TextEditingController()));
  }

  void _removePollOption(int index) {
    if (_pollOptionControllers.length <= 2) return;
    final controller = _pollOptionControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  Board? get _selectedBoard {
    for (final b in widget.boards) {
      if (b.id == _selectedBoardId) return b;
    }
    return null;
  }

  void _submit() {
    final l10n = context.l10n;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (widget.boards.isEmpty || _selectedBoardId == null) {
      setState(() => _error = l10n.hostedBoardRequired);
      return;
    }
    if (title.isEmpty) {
      setState(() => _error = l10n.titleRequired);
      return;
    }
    if (content.isEmpty) {
      setState(() => _error = l10n.contentRequired);
      return;
    }
    final pollOptions = _pollOptionControllers
        .map((controller) => controller.text.trim())
        .where((option) => option.isNotEmpty)
        .toList();
    if (_isPoll && pollOptions.length < 2) {
      setState(() => _error = '投票至少需要兩個選項。');
      return;
    }
    Navigator.of(context).pop<Map<String, Object?>>({
      'boardId': _selectedBoardId,
      'title': title,
      'content': content,
      'crossPostTargetIds': _selectedCrossPostIds.toList(),
      'publicationDeferred': _publicationDeferred,
      if (_isPoll)
        'poll': {
          'options': [
            for (var index = 0; index < pollOptions.length; index++)
              {'id': 'option-${index + 1}', 'label': pollOptions[index]},
          ],
          if (_pollDurationDays != null)
            'closes_at': DateTime.now()
                .toUtc()
                .add(Duration(days: _pollDurationDays!))
                .toIso8601String(),
        },
    });
  }

  Future<void> _pickBoard() async {
    if (widget.boards.length <= 1) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AnsibleDesign.paper,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final b in widget.boards)
              ListTile(
                leading: Icon(
                  b.id == _selectedBoardId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: AnsibleDesign.accent,
                ),
                title: Text(b.title),
                onTap: () => Navigator.of(sheetContext).pop(b.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() => _selectedBoardId = chosen);
      unawaited(_loadBoardPolicy());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onCancel: () => Navigator.of(context).pop(),
              onDone: _submit,
              isPoll: _isPoll,
            ),
            if (_error != null) _ErrorBanner(message: _error!),
            _BoardSelector(
              label: l10n.chooseHostedBoard,
              boardTitle: _selectedBoard?.title ?? l10n.hostedBoardMissing,
              canChange: widget.boards.length > 1,
              onTap: _pickBoard,
            ),
            if (_publicationDeferred)
              _PostingGateBanner(writeEnabled: _writeEnabled),
            if (!_publicationDeferred && _crossPostTargets.isNotEmpty)
              _CrossPostSelector(
                targets: _crossPostTargets,
                selectedIds: _selectedCrossPostIds,
                onToggle: (subscriptionId, selected) => setState(() {
                  if (selected) {
                    _selectedCrossPostIds.add(subscriptionId);
                  } else {
                    _selectedCrossPostIds.remove(subscriptionId);
                  }
                }),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Theme(
                      // The app-wide dark selection colour made selected ink
                      // text unreadable on this fixed Paper composer surface.
                      data: Theme.of(context).copyWith(
                        textSelectionTheme: TextSelectionThemeData(
                          cursorColor: AnsibleDesign.ink,
                          selectionColor: AnsibleDesign.accent.withValues(
                            alpha: 0.58,
                          ),
                          selectionHandleColor: AnsibleDesign.accent,
                        ),
                      ),
                      child: TextField(
                        key: const Key('thread_composer_title_field'),
                        controller: _titleController,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        cursorColor: AnsibleDesign.ink,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 28,
                          height: 1.2,
                          color: AnsibleDesign.ink,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          // The composer surface is always Paper, even when
                          // the rest of the app follows the system dark theme.
                          // Do not inherit darkTheme's filled input background.
                          filled: false,
                          isDense: true,
                          hintText: l10n.discussionTitleHint,
                          hintStyle: const TextStyle(
                            color: AnsibleDesign.inkFaint,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                          ),
                          border: const UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AnsibleDesign.ruleSoft,
                              width: 0.5,
                            ),
                          ),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AnsibleDesign.ruleSoft,
                              width: 0.5,
                            ),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AnsibleDesign.accent,
                              width: 1,
                            ),
                          ),
                          contentPadding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                        ),
                      ),
                    ),
                    if (_isPoll) ...[
                      const SizedBox(height: 18),
                      _PollOptionsEditor(
                        controllers: _pollOptionControllers,
                        onAdd: _addPollOption,
                        onRemove: _removePollOption,
                        durationDays: _pollDurationDays,
                        onDurationChanged: (value) =>
                            setState(() => _pollDurationDays = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('thread_composer_body_field'),
                      controller: _contentController,
                      minLines: 6,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      cursorColor: AnsibleDesign.ink,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: AnsibleDesign.readingTextSize,
                        height: 1.8,
                        color: AnsibleDesign.ink,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        hintText: l10n.discussionContentHint,
                        hintStyle: const TextStyle(
                          color: AnsibleDesign.inkFaint,
                          fontSize: AnsibleDesign.readingTextSize,
                          height: 1.8,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Footer(
              did: widget.authorDid,
              characterCount: _contentController.text.characters.length,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onCancel,
    required this.onDone,
    required this.isPoll,
  });

  final VoidCallback onCancel;

  /// Null disables the create button (e.g. posting gate not cleared).
  final VoidCallback? onDone;
  final bool isPoll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 17),
            label: Text(l10n.cancel),
            style: TextButton.styleFrom(
              foregroundColor: AnsibleDesign.inkMuted,
              textStyle: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          Text(
            context.uiCopy(
              zh: isPoll ? '新投票 · NEW POLL' : '新討論 · NEW DISCUSSION',
              en: isPoll ? 'NEW POLL' : 'NEW DISCUSSION',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 14),
          FilledButton(
            key: const Key('thread_composer_done_button'),
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: AnsibleDesign.paperElev,
              foregroundColor: AnsibleDesign.ink,
              side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 34),
            ),
            child: Text(
              l10n.create,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollOptionsEditor extends StatelessWidget {
  const _PollOptionsEditor({
    required this.controllers,
    required this.onAdd,
    required this.onRemove,
    required this.durationDays,
    required this.onDurationChanged,
  });

  final List<TextEditingController> controllers;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final int? durationDays;
  final ValueChanged<int?> onDurationChanged;

  @override
  Widget build(BuildContext context) {
    final atLimit = controllers.length >= 12;
    return Container(
      key: const Key('thread_composer_poll_editor'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paperElev,
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.poll_outlined,
                size: 18,
                color: AnsibleDesign.accent,
              ),
              const SizedBox(width: 8),
              Text(
                context.uiCopy(zh: '投票選項', en: 'Poll options'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AnsibleDesign.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${controllers.length}/12',
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            context.uiCopy(
              zh: '討論標題就是投票題目；至少填寫兩個選項。僅具本版發言資格者可投票。',
              en: 'The discussion title is the question. Add at least two options; only eligible board speakers can vote.',
            ),
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          for (var index = 0; index < controllers.length; index++)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('thread_composer_poll_option_$index'),
                      controller: controllers[index],
                      cursorColor: AnsibleDesign.ink,
                      style: const TextStyle(color: AnsibleDesign.ink),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AnsibleDesign.paper,
                        labelText: context.uiCopy(
                          zh: '選項 ${index + 1}',
                          en: 'Option ${index + 1}',
                        ),
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        labelStyle: const TextStyle(
                          color: AnsibleDesign.inkMuted,
                        ),
                        border: const OutlineInputBorder(
                          borderSide: BorderSide(color: AnsibleDesign.rule),
                        ),
                      ),
                    ),
                  ),
                  if (controllers.length > 2)
                    IconButton(
                      key: Key('thread_composer_remove_poll_option_$index'),
                      tooltip: context.uiCopy(zh: '移除此選項', en: 'Remove option'),
                      onPressed: () => onRemove(index),
                      icon: const Icon(Icons.remove_circle_outline),
                      color: AnsibleDesign.inkMuted,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('thread_composer_add_poll_option'),
            onPressed: atLimit ? null : onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.uiCopy(zh: '新增選項', en: 'Add option')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AnsibleDesign.ink,
              side: const BorderSide(color: AnsibleDesign.rule),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            key: const Key('thread_composer_poll_duration'),
            initialValue: durationDays,
            decoration: InputDecoration(
              filled: true,
              fillColor: AnsibleDesign.paper,
              labelText: context.uiCopy(zh: '結束時間', en: 'Ends'),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              labelStyle: const TextStyle(color: AnsibleDesign.inkMuted),
              border: const OutlineInputBorder(
                borderSide: BorderSide(color: AnsibleDesign.rule),
              ),
            ),
            dropdownColor: AnsibleDesign.paper,
            style: const TextStyle(color: AnsibleDesign.ink),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(context.uiCopy(zh: '不設定', en: 'No end date')),
              ),
              for (final days in [1, 3, 7])
                DropdownMenuItem<int?>(
                  value: days,
                  child: Text(
                    context.uiCopy(zh: '$days 天後', en: 'In $days days'),
                  ),
                ),
            ],
            onChanged: onDurationChanged,
          ),
        ],
      ),
    );
  }
}

class _BoardSelector extends StatelessWidget {
  const _BoardSelector({
    required this.label,
    required this.boardTitle,
    required this.canChange,
    required this.onTap,
  });

  final String label;
  final String boardTitle;
  final bool canChange;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 6),
      child: InkWell(
        onTap: canChange ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AnsibleDesign.rule, width: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 15,
                color: AnsibleDesign.inkMuted,
              ),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 9,
                  color: AnsibleDesign.inkFaint,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  boardTitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AnsibleDesign.ink,
                  ),
                ),
              ),
              if (canChange)
                const Icon(
                  Icons.unfold_more,
                  size: 16,
                  color: AnsibleDesign.inkMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.did, required this.characterCount});

  final String? did;
  final int characterCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 10),
      decoration: const BoxDecoration(
        color: AnsibleDesign.paper,
        border: Border(
          top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (did != null && did!.isNotEmpty) ...[
            const Icon(
              Icons.fingerprint_rounded,
              size: 14,
              color: AnsibleDesign.accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                did!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 11,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
            ),
          ] else
            const Spacer(),
          Text(
            context.uiCopy(
              zh: '$characterCount 字',
              en: '$characterCount chars',
            ),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline explanation shown when the selected board's posting gate is not
/// cleared: the gate must be discoverable before posting (Base Rule 6). The
/// submit button is disabled while this banner is visible; the relay remains
/// the enforcement source of truth.
class _PostingGateBanner extends StatelessWidget {
  const _PostingGateBanner({required this.writeEnabled});

  final bool writeEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('composer_posting_gate_banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 2, 22, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AnsibleDesign.accent.withValues(alpha: 0.08),
        border: Border.all(
          color: AnsibleDesign.accent.withValues(alpha: 0.4),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_outlined,
            size: 16,
            color: AnsibleDesign.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.uiCopy(
                zh: writeEnabled
                    ? '你目前未符合此看板的發文資格。內容仍會安全保存在本機，取得資格後可在同步時重新發佈。'
                    : '你目前只有閱讀權限。內容會先保存為本機草稿，不會在取得發文資格前送到看板。',
                en: writeEnabled
                    ? 'You do not currently meet this board’s posting rule. '
                          'The content stays safely on this device and can be '
                          'retried after you qualify.'
                    : 'You currently have read-only access. This content will '
                          'be kept as a local draft and will not reach the '
                          'board until posting access is available.',
              ),
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional multi-select of other subscribed writable boards to cross-post
/// the new thread to ("同時發佈到…").
class _CrossPostSelector extends StatelessWidget {
  const _CrossPostSelector({
    required this.targets,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<_CrossPostTarget> targets;
  final Set<String> selectedIds;
  final void Function(String subscriptionId, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.uiCopy(zh: '同時發佈到…', en: 'ALSO POST TO…'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: AnsibleDesign.inkFaint,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final target in targets)
                FilterChip(
                  key: Key('cross_post_target_${target.subscriptionId}'),
                  label: Text(target.boardTitle),
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    color: AnsibleDesign.ink,
                  ),
                  selected: selectedIds.contains(target.subscriptionId),
                  onSelected: (selected) =>
                      onToggle(target.subscriptionId, selected),
                  backgroundColor: AnsibleDesign.paper,
                  selectedColor: AnsibleDesign.paperDeep,
                  checkmarkColor: AnsibleDesign.accent,
                  side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(22, 4, 22, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AnsibleDesign.danger.withValues(alpha: 0.10),
        border: Border.all(color: AnsibleDesign.danger.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AnsibleDesign.danger,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AnsibleDesign.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
