import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    this.displayName = '林下',
    this.handle = 'under-the-canopy',
  });

  final String displayName;
  final String handle;

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: '',
      leadingLabel: '← 討論串',
      trailing: IconButton(
        onPressed: () {},
        icon: const Icon(Icons.more_horiz),
        tooltip: '更多',
      ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AnsibleMonoLabel('公開身分 · PUBLIC HANDLE'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AnsibleDesign.paperDeep,
                        border: Border.all(
                          color: AnsibleDesign.rule,
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        displayName.characters.first,
                        style: const TextStyle(
                          fontSize: 26,
                          color: AnsibleDesign.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: AnsibleDesign.ink,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            handle,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AnsibleDesign.inkMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'pk · a3f1 … 2c9b',
                            style: TextStyle(
                              fontFamily: AnsibleDesign.mono,
                              fontSize: 9,
                              letterSpacing: 1.1,
                              color: AnsibleDesign.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  '在台北的某個老房子裡寫字。最近在想 patches、補丁、與不必修復的鬆動感。',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.7,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _ProfileMeta('加入 · 312 天'),
                    _ProfileMeta('3 個共同的圈'),
                    _ProfileMeta('14 分前在線', dot: AnsibleDesign.spore),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {},
                        child: const Text('追蹤公開發布'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: () {}, child: const Text('邀請進圈')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AnsibleDesign.paperDeep.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AnsibleDesign.inkMuted,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '你看到的是「公開 · 林下」這個身分。「圈內」與「本人」對你不可見。',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const AnsibleMonoLabel(
            '公開發布 · PUBLIC · 18',
            padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
          ),
          AnsibleRuleGroup(
            children: const [
              _PublicPostRow(
                tag: 'PHIL',
                title: '我們在「廢墟」裡到底在尋找什麼？',
                sub: '23 回 · 2 小時前',
              ),
              _PublicPostRow(tag: 'NOTE', title: '一個老房子的牆角', sub: '7 回 · 昨日'),
              _PublicPostRow(
                tag: 'PHIL',
                title: '為什麼我們抗拒「重建」這個詞',
                sub: '4 回 · 5 天',
              ),
              _PublicPostRow(
                tag: 'TOOL',
                title: '寫不下去的時候——一個方法',
                sub: '11 回 · 11 天',
                last: true,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ProfileMeta extends StatelessWidget {
  const _ProfileMeta(this.label, {this.dot});

  final String label;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: const TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 9.5,
            letterSpacing: 1,
            color: AnsibleDesign.inkFaint,
          ),
        ),
      ],
    );
  }
}

class _PublicPostRow extends StatelessWidget {
  const _PublicPostRow({
    required this.tag,
    required this.title,
    required this.sub,
    this.last = false,
  });

  final String tag;
  final String title;
  final String sub;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: last
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tag,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 8.5,
              letterSpacing: 1.4,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              color: AnsibleDesign.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              letterSpacing: 1,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
