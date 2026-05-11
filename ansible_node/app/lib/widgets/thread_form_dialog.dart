import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

class ThreadFormDialog extends StatefulWidget {
  const ThreadFormDialog({
    super.key,
    required this.boards,
    this.initialBoardId,
  });

  final List<Board> boards;
  final String? initialBoardId;

  @override
  State<ThreadFormDialog> createState() => _ThreadFormDialogState();
}

class _ThreadFormDialogState extends State<ThreadFormDialog> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedBoardId;

  @override
  void initState() {
    super.initState();
    _selectedBoardId =
        widget.initialBoardId ??
        (widget.boards.isNotEmpty ? widget.boards.first.id : null);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasBoards = widget.boards.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.createDiscussion),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedBoardId,
              items: widget.boards
                  .map(
                    (b) => DropdownMenuItem(value: b.id, child: Text(b.title)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedBoardId = value),
              decoration: InputDecoration(labelText: l10n.chooseHostedBoard),
              validator: (_) {
                if (!hasBoards) return l10n.hostedBoardMissing;
                if (_selectedBoardId == null || _selectedBoardId!.isEmpty) {
                  return l10n.hostedBoardRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l10n.titleLabel,
                hintText: l10n.discussionTitleHint,
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.titleRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contentController,
              decoration: InputDecoration(
                labelText: l10n.contentLabel,
                hintText: l10n.discussionContentHint,
              ),
              minLines: 3,
              maxLines: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return l10n.contentRequired;
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'boardId': _selectedBoardId,
                'title': _titleController.text.trim(),
                'content': _contentController.text.trim(),
              });
            }
          },
          child: Text(l10n.create),
        ),
      ],
    );
  }
}
