import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class MurmurDetailScreen extends StatelessWidget {
  const MurmurDetailScreen({super.key, required this.murmur});

  final ContentItem murmur;

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: 'MURMUR',
      leadingLabel: '← 草地',
      trailing: IconButton(
        onPressed: () {},
        icon: const Icon(Icons.more_horiz),
        tooltip: '更多',
      ),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Row(
              children: [
                Text(
                  _formatDateTime(murmur.createdAt),
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1.4,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Divider(color: AnsibleDesign.rule, thickness: 0.5),
                ),
                const SizedBox(width: 10),
                AnsibleStatusChip(
                  label: _visibilityLabel(murmur.visibility),
                  dot: _visibilityColor(murmur.visibility),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.only(left: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AnsibleDesign.accent, width: 2),
                    ),
                  ),
                  child: Text(
                    murmur.body,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.55,
                      color: AnsibleDesign.ink,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _Meta('${murmur.body.characters.length} 字'),
                    const _Meta('0 個 note 引用了它'),
                    const _Meta('0 次被討論'),
                  ],
                ),
              ],
            ),
          ),
          const AnsibleMonoLabel(
            '長進了 · GREW INTO',
            padding: EdgeInsets.fromLTRB(22, 6, 22, 10),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: [
                _LineageRow(
                  title: '廢墟中的協作',
                  when: '2 天後',
                  count: 6,
                  color: AnsibleDesign.accent,
                ),
                _LineageRow(
                  title: '荒涼感作為一種介面語言',
                  when: '5 天後',
                  count: 4,
                  color: AnsibleDesign.spore,
                ),
                _LineageRow(
                  title: '為什麼我們抗拒重建',
                  when: '11 天後',
                  count: 8,
                  color: AnsibleDesign.inkMuted,
                  last: true,
                ),
                _GrowthHint(),
              ],
            ),
          ),
          const AnsibleMonoLabel(
            '被引用 · QUOTED · 1',
            padding: EdgeInsets.fromLTRB(22, 20, 22, 8),
          ),
          const AnsibleRuleGroup(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'THRD · PHIL',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 8.5,
                            letterSpacing: 1.4,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '1 小時前',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '我們在「廢墟」裡到底在尋找什麼？',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AnsibleDesign.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'kr.：「凹陷處停留」這個說法很準。',
                      style: TextStyle(
                        fontSize: 12,
                        color: AnsibleDesign.inkMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}·${local.month.toString().padLeft(2, '0')}·${local.day.toString().padLeft(2, '0')} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _visibilityLabel(ContentVisibility visibility) {
    return switch (visibility) {
      ContentVisibility.private => '私人',
      ContentVisibility.unlisted => '圈內',
      ContentVisibility.public => '公開',
    };
  }

  static Color _visibilityColor(ContentVisibility visibility) {
    return switch (visibility) {
      ContentVisibility.private => AnsibleDesign.inkMuted,
      ContentVisibility.unlisted => AnsibleDesign.accent,
      ContentVisibility.public => AnsibleDesign.spore,
    };
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontFamily: AnsibleDesign.mono,
        fontSize: 10,
        letterSpacing: 1,
        color: AnsibleDesign.inkFaint,
      ),
    );
  }
}

class _LineageRow extends StatelessWidget {
  const _LineageRow({
    required this.title,
    required this.when,
    required this.count,
    required this.color,
    this.last = false,
  });

  final String title;
  final String when;
  final int count;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 14,
          height: 72,
          child: Stack(
            children: [
              Positioned(
                left: 6,
                top: 0,
                bottom: last ? 36 : 0,
                child: Container(width: 0.5, color: AnsibleDesign.rule),
              ),
              Positioned(
                left: 3,
                top: 18,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AnsibleDesign.paper,
                    border: Border.all(color: AnsibleDesign.ink, width: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: last
                    ? BorderSide.none
                    : const BorderSide(
                        color: AnsibleDesign.ruleSoft,
                        width: 0.5,
                      ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'NOTE',
                      style: TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 8.5,
                        letterSpacing: 1.4,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      when,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '與另外 ${count - 1} 個 murmur 一起構成',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GrowthHint extends StatelessWidget {
  const _GrowthHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(28, 12, 0, 0),
      child: Text(
        '還可以再長下去：把它放進新的筆記',
        style: TextStyle(
          fontSize: 12.5,
          color: AnsibleDesign.inkFaint,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
