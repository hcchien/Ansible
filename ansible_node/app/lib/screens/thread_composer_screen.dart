import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Full-screen composer for a new forum discussion, styled to match the app's
/// design system (mirrors [NoteEditorScreen]'s chrome). Replaces the old
/// Material `AlertDialog`. Pops `{boardId, title, content}` on submit, or null
/// on cancel — the same contract the caller already consumes.
class ThreadComposerScreen extends StatefulWidget {
  const ThreadComposerScreen({
    super.key,
    required this.boards,
    this.initialBoardId,
    this.authorDid,
  });

  final List<Board> boards;
  final String? initialBoardId;

  /// Shown in the footer for parity with the note editor. Optional.
  final String? authorDid;

  @override
  State<ThreadComposerScreen> createState() => _ThreadComposerScreenState();
}

class _ThreadComposerScreenState extends State<ThreadComposerScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String? _selectedBoardId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedBoardId =
        widget.initialBoardId ??
        (widget.boards.isNotEmpty ? widget.boards.first.id : null);
    _titleController.addListener(() => setState(() {}));
    _contentController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
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
    Navigator.of(context).pop<Map<String, String?>>({
      'boardId': _selectedBoardId,
      'title': title,
      'content': content,
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
    if (chosen != null) setState(() => _selectedBoardId = chosen);
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
            _TopBar(onCancel: () => Navigator.of(context).pop(), onDone: _submit),
            if (_error != null) _ErrorBanner(message: _error!),
            _BoardSelector(
              label: l10n.chooseHostedBoard,
              boardTitle: _selectedBoard?.title ?? l10n.hostedBoardMissing,
              canChange: widget.boards.length > 1,
              onTap: _pickBoard,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('thread_composer_title_field'),
                      controller: _titleController,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.2,
                        color: AnsibleDesign.ink,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
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
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('thread_composer_body_field'),
                      controller: _contentController,
                      minLines: 6,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
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
  const _TopBar({required this.onCancel, required this.onDone});

  final VoidCallback onCancel;
  final VoidCallback onDone;

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
            context.uiCopy(zh: '新討論 · NEW', en: 'NEW DISCUSSION'),
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
            context.uiCopy(zh: '$characterCount 字', en: '$characterCount chars'),
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
