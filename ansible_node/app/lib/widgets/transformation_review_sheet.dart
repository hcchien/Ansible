import 'package:flutter/material.dart';

typedef TransformationAccept =
    Future<void> Function(String? title, String body);

class TransformationReviewSheet extends StatefulWidget {
  const TransformationReviewSheet({
    super.key,
    required this.title,
    required this.body,
    required this.sourceLabels,
    required this.onAccept,
    this.containsPrivateSource = false,
  });

  final String? title;
  final String body;
  final List<String> sourceLabels;
  final bool containsPrivateSource;
  final TransformationAccept onAccept;

  @override
  State<TransformationReviewSheet> createState() =>
      _TransformationReviewSheetState();
}

class _TransformationReviewSheetState extends State<TransformationReviewSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title ?? '');
    _bodyController = TextEditingController(text: widget.body);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _saving = true);
    await widget.onAccept(
      _titleController.text.trim().isEmpty ? null : _titleController.text,
      _bodyController.text,
    );
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '轉換審閱',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text('來源邊界', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in widget.sourceLabels)
                  Chip(label: Text(label)),
                if (widget.containsPrivateSource)
                  const Chip(label: Text('Private/local source')),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('transformation_body_field'),
              controller: _bodyController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'Generated output'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Discard'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _accept,
                  icon: const Icon(Icons.check),
                  label: const Text('接受'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
