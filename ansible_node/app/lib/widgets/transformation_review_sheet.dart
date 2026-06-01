import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

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
          left: 22,
          right: 22,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: AnsibleDesign.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const AnsibleMark(size: 18),
                const SizedBox(width: 10),
                Text(
                  context.uiCopy(
                    zh: 'SYSTEM MESSAGE · 系統訊息',
                    en: 'SYSTEM MESSAGE',
                  ),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    color: AnsibleDesign.inkMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.uiCopy(
                zh: '下面這些內容會離開你的裝置，傳送給遠端 AI 做整理。',
                en: 'The following content will leave your device and be sent to a remote AI for processing.',
              ),
              style: const TextStyle(
                fontSize: 17,
                height: 1.65,
                color: AnsibleDesign.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.uiCopy(
                zh: '一旦傳出，就無法當作沒發生過。可以先把不想送的關掉。',
                en: 'Once sent, it cannot be treated as if it never happened. Turn off anything you do not want to send.',
              ),
              style: const TextStyle(
                fontSize: 13,
                height: 1.65,
                color: AnsibleDesign.inkMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: AnsibleDesign.ruleSoft,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _ManifestRow(
                    kind: context.uiCopy(zh: '正文 · BODY', en: 'BODY'),
                    detail: context.uiCopy(
                      zh: '${widget.body.length} 字',
                      en: '${widget.body.length} chars',
                    ),
                    enabled: true,
                    locked: true,
                  ),
                  if (widget.containsPrivateSource)
                    _ManifestRow(
                      kind: 'PRIVATE · LOCAL SOURCE',
                      detail: context.uiCopy(
                        zh: '來源內容預設留在本地；送出前需明確確認',
                        en: 'Source content stays local by default and needs explicit confirmation before sending.',
                      ),
                      enabled: true,
                    ),
                  for (final label in widget.sourceLabels)
                    _ManifestRow(
                      kind: context.uiCopy(zh: '來源 · SOURCE', en: 'SOURCE'),
                      detail: label,
                      enabled: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: context.uiCopy(zh: '標題 · TITLE', en: 'Title'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('transformation_body_field'),
              controller: _bodyController,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(height: 1.55),
              decoration: InputDecoration(
                labelText: context.uiCopy(zh: '整理結果 · OUTPUT', en: 'Output'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(context.uiCopy(zh: '留在本地', en: 'Keep Local')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _accept,
                    child: Text(
                      context.uiCopy(
                        zh: '送出 · 約 ${widget.body.length} 字',
                        en: 'Send · about ${widget.body.length} chars',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ManifestRow extends StatelessWidget {
  const _ManifestRow({
    required this.kind,
    required this.detail,
    required this.enabled,
    this.locked = false,
  });

  final String kind;
  final String detail;
  final bool enabled;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1.3,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 13,
                    color: enabled ? AnsibleDesign.ink : AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Opacity(
            opacity: locked ? 0.45 : 1,
            child: Container(
              width: 36,
              height: 20,
              decoration: BoxDecoration(
                color: enabled ? AnsibleDesign.ink : AnsibleDesign.paperDeep,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AnsibleDesign.rule, width: 0.5),
              ),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              padding: const EdgeInsets.all(2),
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AnsibleDesign.paper,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
