import 'package:flutter/material.dart';

class PostFormDialog extends StatefulWidget {
  final String? initialContent;

  const PostFormDialog({super.key, this.initialContent});

  @override
  State<PostFormDialog> createState() => _PostFormDialogState();
}

class _PostFormDialogState extends State<PostFormDialog> {
  late final TextEditingController _contentController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialContent == null ? 'New Post' : 'Edit Post'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _contentController,
          decoration: const InputDecoration(
            labelText: 'Content',
            hintText: 'Enter your post content',
            border: OutlineInputBorder(),
          ),
          maxLines: 5,
          autofocus: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Content is required';
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
              Navigator.pop(context, _contentController.text.trim());
            }
          },
          child: const Text('Post'),
        ),
      ],
    );
  }
}
