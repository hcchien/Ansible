import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../widgets/summary_review_sheet.dart';

typedef SaveSummaryAsNote = Future<void> Function(String summary);

class DiscussionDetailScreen extends StatelessWidget {
  const DiscussionDetailScreen({
    super.key,
    required this.title,
    required this.body,
    this.onSaveSummaryAsNote,
  });

  final String title;
  final String body;
  final SaveSummaryAsNote? onSaveSummaryAsNote;

  Future<void> _openSummaryReview(BuildContext context) async {
    final summary =
        '$title: ${body.isEmpty ? 'No discussion body yet.' : body}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF0C1424),
      builder: (_) => SummaryReviewSheet(
        summary: summary,
        sourceLabels: [title],
        onSaveAsNote: onSaveSummaryAsNote ?? (_) async {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(body, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _openSummaryReview(context),
                icon: const Icon(Icons.auto_awesome),
                label: Text(context.uiCopy(zh: 'AI 摘要', en: 'AI Summary')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
