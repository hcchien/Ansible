import 'package:flutter/widgets.dart';

import 'app_l10n.dart';

/// Bilingual labels for the fixed moderation reason-code enum (the single
/// localization point for reason codes shown in moderation outcomes:
/// tombstones, lock banners, lock tooltips, and notifications).
///
/// Codes mirror the relay's `ReportReason` enum: spam, harassment,
/// illegal_content, off_topic, impersonation, other.
String moderationReasonLabel(BuildContext context, String reasonCode) {
  return switch (reasonCode) {
    'spam' => context.uiCopy(zh: '垃圾訊息', en: 'spam'),
    'harassment' => context.uiCopy(zh: '騷擾或攻擊', en: 'harassment'),
    'illegal_content' => context.uiCopy(zh: '不法內容', en: 'illegal content'),
    'off_topic' => context.uiCopy(zh: '離題', en: 'off topic'),
    'impersonation' => context.uiCopy(zh: '冒充他人', en: 'impersonation'),
    'other' => context.uiCopy(zh: '其他', en: 'other'),
    _ => reasonCode,
  };
}
