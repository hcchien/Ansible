import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = [
      _InboxGroup('回應 · REPLIES', [
        _InboxItem(
          who: 'kr.',
          where: '廢墟中的協作',
          text: '我在想 patches 翻譯成「斑塊」太冷了——',
          when: '14:22',
          unread: true,
          accent: AnsibleDesign.accent,
        ),
        _InboxItem(
          who: '林下',
          where: 'Le Guin 的 Ansible',
          text: '你提到的「延遲」讓我想起 Stand on Zanzibar——',
          when: '13:08',
          unread: true,
          accent: AnsibleDesign.spore,
        ),
        _InboxItem(
          who: '路過的人',
          where: '一朵不認識的菇',
          text: '+1 林下這段。',
          when: '昨 22:14',
        ),
      ]),
      _InboxGroup('圈內 · CIRCLE', [
        _InboxItem(
          who: '週四讀書會',
          where: '林下',
          text: '加入了「廢墟中的協作」共讀',
          when: '今晨',
          unread: true,
          system: true,
        ),
        _InboxItem(
          who: '同居寫作組',
          where: 'kr.',
          text: '邀請了路過的人加入',
          when: '昨日',
          system: true,
        ),
      ]),
      _InboxGroup('裝置 · SYNC', [
        _InboxItem(
          who: 'iPad mini',
          text: '同步了 6 個 murmur · 11 篇筆記',
          when: '11:40',
          system: true,
          sync: true,
        ),
        _InboxItem(
          who: '舊手機',
          text: '已暫停同步 14 天',
          when: '2 週前',
          system: true,
          sync: true,
          dim: true,
        ),
      ]),
    ];

    return AnsibleScreenScaffold(
      title: 'INBOX',
      leadingLabel: '← 草地',
      trailing: TextButton(
        onPressed: () {},
        child: const Text(
          '全部已讀',
          style: TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
      ),
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnsibleMonoLabel('收信 · INBOX'),
                SizedBox(height: 4),
                Text(
                  '這一陣子',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '3 個還沒讀。其他都不急。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AnsibleDesign.inkFaint,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          for (final group in groups) _InboxGroupView(group: group),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 24, 22, 32),
            child: Text(
              '14 天前的都已歸檔',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: AnsibleDesign.inkFaint,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxGroupView extends StatelessWidget {
  const _InboxGroupView({required this.group});

  final _InboxGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnsibleMonoLabel(
          group.label,
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
        ),
        AnsibleRuleGroup(
          children: [
            for (var i = 0; i < group.items.length; i += 1)
              _InboxRow(
                item: group.items[i],
                last: i == group.items.length - 1,
              ),
          ],
        ),
      ],
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.last});

  final _InboxItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: item.dim ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: item.unread
              ? AnsibleDesign.paperDeep.withValues(alpha: 0.45)
              : Colors.transparent,
          border: Border(
            bottom: last
                ? BorderSide.none
                : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 8,
                child: item.unread
                    ? Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 10),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AnsibleDesign.accent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              _InboxAvatar(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.who,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AnsibleDesign.ink,
                              fontWeight: item.unread
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (item.where.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Text(
                            '·',
                            style: TextStyle(
                              fontFamily: AnsibleDesign.mono,
                              fontSize: 10,
                              color: AnsibleDesign.inkFaint,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.where,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AnsibleDesign.inkMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          item.when,
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9,
                            letterSpacing: 0.8,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: item.system
                            ? AnsibleDesign.inkMuted
                            : AnsibleDesign.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxAvatar extends StatelessWidget {
  const _InboxAvatar({required this.item});

  final _InboxItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: item.sync ? Colors.transparent : AnsibleDesign.paperDeep,
        borderRadius: BorderRadius.circular(item.sync ? 4 : 999),
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        item.sync ? '↔' : item.who.characters.first,
        style: TextStyle(
          fontFamily: item.sync ? AnsibleDesign.mono : AnsibleDesign.serif,
          fontSize: 12,
          color: item.accent,
        ),
      ),
    );
  }
}

class _InboxGroup {
  const _InboxGroup(this.label, this.items);

  final String label;
  final List<_InboxItem> items;
}

class _InboxItem {
  const _InboxItem({
    required this.who,
    required this.text,
    required this.when,
    this.where = '',
    this.unread = false,
    this.system = false,
    this.sync = false,
    this.dim = false,
    this.accent = AnsibleDesign.inkMuted,
  });

  final String who;
  final String where;
  final String text;
  final String when;
  final bool unread;
  final bool system;
  final bool sync;
  final bool dim;
  final Color accent;
}
