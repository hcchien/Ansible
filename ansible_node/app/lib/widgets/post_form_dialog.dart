import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

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
      title: Text(
        widget.initialContent == null
            ? context.uiCopy(zh: '發表貼文', en: 'New Post')
            : context.uiCopy(zh: '編輯貼文', en: 'Edit Post'),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _contentController,
          decoration: InputDecoration(
            labelText: context.uiCopy(zh: '內容', en: 'Content'),
            hintText: context.uiCopy(zh: '輸入貼文內容', en: 'Enter your post content'),
            border: const OutlineInputBorder(),
          ),
          maxLines: 5,
          autofocus: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return context.uiCopy(zh: '請輸入內容', en: 'Content is required');
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _contentController.text.trim());
            }
          },
          child: Text(context.uiCopy(zh: '發表', en: 'Post')),
        ),
      ],
    );
  }
}
