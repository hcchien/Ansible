import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/forum_host_client.dart';

/// The reporter's chosen reason (+ optional note, required for `other`).
class ReportDraft {
  final String reasonCode;
  final String? note;

  const ReportDraft({required this.reasonCode, this.note});
}

/// Reason picker for reporting a post or thread to its Forum Host.
/// Returns null when cancelled.
Future<ReportDraft?> showReportDialog(BuildContext context) {
  return showDialog<ReportDraft>(
    context: context,
    builder: (context) => const _ReportDialog(),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _reasonCode = ReportContentIntent.reasonCodes.first;
  final _noteController = TextEditingController();
  bool _noteMissing = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String _reasonLabel(BuildContext context, String code) {
    return switch (code) {
      'spam' => context.uiCopy(zh: '垃圾訊息', en: 'Spam'),
      'harassment' => context.uiCopy(zh: '騷擾或攻擊', en: 'Harassment'),
      'illegal_content' => context.uiCopy(zh: '不法內容', en: 'Illegal content'),
      'off_topic' => context.uiCopy(zh: '離題', en: 'Off topic'),
      'impersonation' => context.uiCopy(zh: '冒充他人', en: 'Impersonation'),
      _ => context.uiCopy(zh: '其他（請說明）', en: 'Other (explain)'),
    };
  }

  void _submit() {
    final note = _noteController.text.trim();
    if (_reasonCode == 'other' && note.isEmpty) {
      setState(() => _noteMissing = true);
      return;
    }
    Navigator.pop(
      context,
      ReportDraft(reasonCode: _reasonCode, note: note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.uiCopy(zh: '檢舉內容', en: 'Report content')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.uiCopy(
                zh: '檢舉會以你的身分簽章送交看板的管理者，由板務依板規處理。',
                en:
                    'Reports are signed with your identity and handled by '
                    'the board moderators under the board rules.',
              ),
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _reasonCode,
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _reasonCode = value;
                    _noteMissing = false;
                  });
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final code in ReportContentIntent.reasonCodes)
                    RadioListTile<String>(
                      key: Key('report_reason_$code'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_reasonLabel(context, code)),
                      value: code,
                    ),
                ],
              ),
            ),
            TextField(
              key: const Key('report_note_field'),
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: context.uiCopy(zh: '補充說明', en: 'Note'),
                errorText: _noteMissing
                    ? context.uiCopy(
                        zh: '選擇「其他」時請填寫說明',
                        en: 'A note is required for "Other"',
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.uiCopy(zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          key: const Key('report_submit_button'),
          onPressed: _submit,
          child: Text(context.uiCopy(zh: '送出檢舉', en: 'Submit report')),
        ),
      ],
    );
  }
}
