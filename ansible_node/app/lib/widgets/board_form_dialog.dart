import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/posting_gate.dart';

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

  /// `posting_policy.min_post_tier` for the new board; null ⇒ no gate.
  String? _minPostTier;

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
            ? context.uiCopy(zh: '建立託管看板', en: 'Create hosted board')
            : context.uiCopy(zh: '編輯託管看板', en: 'Edit hosted board'),
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
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: 'Elix Relay', en: 'Elix Relay'),
                ),
                validator: (_) {
                  if (!widget.requireForumHost) return null;
                  if (_selectedForumHostId == null ||
                      _selectedForumHostId!.isEmpty) {
                    return context.uiCopy(
                      zh: '請選擇 Elix Relay',
                      en: 'Select an Elix Relay',
                    );
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: context.uiCopy(zh: '標題', en: 'Title'),
                hintText: context.uiCopy(
                  zh: '輸入託管看板標題',
                  en: 'Enter hosted board title',
                ),
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.uiCopy(zh: '請輸入標題', en: 'Title is required');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: context.uiCopy(
                  zh: '描述（選填）',
                  en: 'Description (optional)',
                ),
                hintText: context.uiCopy(
                  zh: '輸入看板描述',
                  en: 'Enter board description',
                ),
              ),
              maxLines: 3,
            ),
            if (widget.requireForumHost) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _minPostTier,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.uiCopy(zh: '不限', en: 'Anyone')),
                  ),
                  DropdownMenuItem<String?>(
                    value: PostingGate.verifiedHumanTier,
                    child: Text(
                      context.uiCopy(zh: '需真人驗證', en: 'Verified humans only'),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _minPostTier = value);
                },
                decoration: InputDecoration(
                  labelText: context.uiCopy(zh: '發文資格', en: 'Who can post'),
                  helperText: context.uiCopy(
                    zh: '僅限制發文；任何人都能閱讀。',
                    en: 'Restricts posting only; anyone can read.',
                  ),
                ),
              ),
            ],
          ],
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
              final description = _descriptionController.text.trim();
              Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'description': description.isEmpty ? null : description,
                if (_selectedForumHostId != null)
                  'forumHostId': _selectedForumHostId,
                if (_minPostTier != null) 'minPostTier': _minPostTier,
              });
            }
          },
          child: Text(context.uiCopy(zh: '儲存', en: 'Save')),
        ),
      ],
    );
  }
}
