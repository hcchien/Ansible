import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

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
    _selectedBoardId = widget.initialBoardId ?? (widget.boards.isNotEmpty ? widget.boards.first.id : null);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasBoards = widget.boards.isNotEmpty;
    return AlertDialog(
      title: const Text('建立討論'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedBoardId,
              items: widget.boards
                  .map(
                    (b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(b.title),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedBoardId = value),
              decoration: const InputDecoration(labelText: '選擇看板'),
              validator: (_) {
                if (!hasBoards) return '請先建立看板';
                if (_selectedBoardId == null || _selectedBoardId!.isEmpty) {
                  return '請選擇看板';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '標題',
                hintText: '輸入討論標題',
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '標題為必填';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: '內容',
                hintText: '輸入討論內容',
              ),
              minLines: 3,
              maxLines: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '內容為必填';
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
          child: const Text('取消'),
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
          child: const Text('建立'),
        ),
      ],
    );
  }
}
