import 'package:flutter/material.dart';
import '../l10n/app_l10n.dart';

/// Signature and personhood are independent assertions, with distinct icons.
class ContentTrustBadge extends StatelessWidget {
  const ContentTrustBadge({
    super.key,
    required this.human,
    required this.color,
  });
  final bool human;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final title = human
        ? context.uiCopy(zh: '真人資格', en: 'Human qualification')
        : context.uiCopy(zh: '已驗證作者簽章', en: 'Author signature verified');
    return IconButton(
      tooltip: title,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(4),
      icon: Icon(
        human ? Icons.person_outline : Icons.verified_outlined,
        size: 17,
        color: color,
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(
            human
                ? context.uiCopy(
                    zh: '作者具有經驗證的真人資格。這不表示平台認可此人或這篇內容。',
                    en: 'The author has a verified human qualification. This does not endorse the person or the content.',
                  )
                : context.uiCopy(
                    zh: '這篇內容的作者簽章已通過驗證。簽章確認來源與內容完整性，不代表內容為真，也不等於真人資格。',
                    en: 'The author signature has been verified. It establishes provenance and integrity, not factual accuracy or human qualification.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.uiCopy(zh: '知道了', en: 'Got it')),
            ),
          ],
        ),
      ),
    );
  }
}
