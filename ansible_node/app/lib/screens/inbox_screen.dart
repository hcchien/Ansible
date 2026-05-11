import 'package:flutter/material.dart';

import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return AnsibleScreenScaffold(
      title: 'INBOX',
      leadingLabel: text.t('backWorkspace'),
      child: const _EmptyInbox(),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: [
        AnsibleMonoLabel(text.t('inboxLabel')),
        const SizedBox(height: 4),
        Text(
          text.t('inboxHero'),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: AnsibleDesign.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text.t('inboxSubtitle'),
          style: const TextStyle(
            fontSize: 12.5,
            color: AnsibleDesign.inkFaint,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          decoration: BoxDecoration(
            color: AnsibleDesign.paperElev,
            border: Border.all(color: AnsibleDesign.ruleSoft, width: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const AnsibleGlyphBox(glyph: '◐'),
              const SizedBox(height: 14),
              Text(
                text.t('emptyInbox'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text.t('emptyInboxBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AnsibleDesign.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
