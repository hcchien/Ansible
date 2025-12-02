import 'package:flutter/material.dart';

class BoardFormDialog extends StatefulWidget {
  final String? initialTitle;
  final String? initialDescription;

  const BoardFormDialog({
    super.key,
    this.initialTitle,
    this.initialDescription,
  });

  @override
  State<BoardFormDialog> createState() => _BoardFormDialogState();
}

class _BoardFormDialogState extends State<BoardFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialTitle == null ? 'Create Board' : 'Edit Board'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter board title',
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Title is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Enter board description',
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final description = _descriptionController.text.trim();
              Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'description': description.isEmpty ? null : description,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
