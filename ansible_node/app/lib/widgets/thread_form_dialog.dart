import 'package:flutter/material.dart';

class ThreadFormDialog extends StatefulWidget {
  const ThreadFormDialog({super.key});

  @override
  State<ThreadFormDialog> createState() => _ThreadFormDialogState();
}

class _ThreadFormDialogState extends State<ThreadFormDialog> {
  final _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Thread'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'Enter thread title',
          ),
          autofocus: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Title is required';
            }
            return null;
          },
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
              Navigator.pop(context, _titleController.text.trim());
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
