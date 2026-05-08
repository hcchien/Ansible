import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnsibleScreenScaffold(
      title: 'INBOX',
      leadingLabel: '← 草地',
      child: _EmptyInbox(),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: [
        const AnsibleMonoLabel('收信 · INBOX'),
        const SizedBox(height: 4),
        const Text(
          '這一陣子',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: AnsibleDesign.ink,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '沒有新的回應、圈內事件或同步通知。',
          style: TextStyle(
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
          child: const Column(
            children: [
              AnsibleGlyphBox(glyph: '◐'),
              SizedBox(height: 14),
              Text(
                '目前沒有收信',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '等有真實回覆、圈內邀請或同步事件時，才會出現在這裡。',
                textAlign: TextAlign.center,
                style: TextStyle(
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
