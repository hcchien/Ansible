import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

class BoardFormDialog extends StatefulWidget {
  final String? initialTitle;
  final String? initialDescription;
  final List<RemoteNode> forumHosts;
  final String? initialForumHostId;
  final bool requireForumHost;

  const BoardFormDialog({
    super.key,
    this.initialTitle,
    this.initialDescription,
    this.forumHosts = const [],
    this.initialForumHostId,
    this.requireForumHost = false,
  });

  @override
  State<BoardFormDialog> createState() => _BoardFormDialogState();
}

class _BoardFormDialogState extends State<BoardFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _formKey = GlobalKey<FormState>();
  String? _selectedForumHostId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _selectedForumHostId =
        widget.initialForumHostId ??
        (widget.forumHosts.isNotEmpty ? widget.forumHosts.first.id : null);
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
      title: Text(
        widget.initialTitle == null
            ? 'Create hosted board'
            : 'Edit hosted board',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.requireForumHost) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedForumHostId,
                items: widget.forumHosts
                    .map(
                      (host) => DropdownMenuItem(
                        value: host.id,
                        child: Text(host.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedForumHostId = value);
                },
                decoration: const InputDecoration(labelText: 'Elix Relay'),
                validator: (_) {
                  if (!widget.requireForumHost) return null;
                  if (_selectedForumHostId == null ||
                      _selectedForumHostId!.isEmpty) {
                    return 'Select an Elix Relay';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter hosted board title',
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
                if (_selectedForumHostId != null)
                  'forumHostId': _selectedForumHostId,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
