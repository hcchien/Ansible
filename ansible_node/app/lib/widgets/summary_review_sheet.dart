import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';

typedef SummarySave = Future<void> Function(String summary);

class SummaryReviewSheet extends StatefulWidget {
  const SummaryReviewSheet({
    super.key,
    required this.summary,
    required this.sourceLabels,
    required this.onSaveAsNote,
  });

  final String summary;
  final List<String> sourceLabels;
  final SummarySave onSaveAsNote;

  @override
  State<SummaryReviewSheet> createState() => _SummaryReviewSheetState();
}

class _SummaryReviewSheetState extends State<SummaryReviewSheet> {
  late final TextEditingController _summaryController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _summaryController = TextEditingController(text: widget.summary);
  }

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSaveAsNote(_summaryController.text);
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
            Text(
              context.uiCopy(zh: '摘要審閱', en: 'Review Summary'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              context.uiCopy(zh: '來源邊界', en: 'Source Boundary'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in widget.sourceLabels)
                  Chip(label: Text(label)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _summaryController,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: 'Summary'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Save as private note'),
            ),
          ],
        ),
      ),
    );
  }
}
