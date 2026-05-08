import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class CredentialAdminScreen extends StatelessWidget {
  const CredentialAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final grants = [
      const _Grant('週四讀書會', 'CIRCLE', '讀書會 · Tris', '寫入 · 讀取', '92 天'),
      const _Grant('公開討論', 'PUBLIC', '公開 · Tris', '只發布', '278 天'),
      const _Grant('Tris ↔ kr.', 'PEER', '本人', '完全互信', '180 天'),
      const _Grant('同居寫作組', 'CIRCLE', '本人', '寫入 · 讀取', '11 天'),
    ];
    final events = [
      const _AuditEvent('kr.', '讀取了「廢墟中的協作」', 'circle handle', '14:22'),
      const _AuditEvent('林下', '回覆了一段', 'public handle', '13:08'),
      const _AuditEvent('iPad', '同步了 6 個 murmur', '本人', '11:40'),
      const _AuditEvent('路過的人', '讀取了公開討論串', 'observer', '昨 22:14'),
      const _AuditEvent('kr.', 'passkey 交換', '本人', '180 天前'),
    ];

    return AnsibleScreenScaffold(
      title: 'ADMIN',
      leadingLabel: '← 設定',
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AnsibleMonoLabel('管理 · ADMIN'),
                const SizedBox(height: 6),
                const Text(
                  '誰看見了哪一個我',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'access & audit',
                  style: TextStyle(
                    fontSize: 13,
                    color: AnsibleDesign.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: _AdminStat(number: '4', label: '正在使用的圈'),
                      ),
                      Expanded(
                        child: _AdminStat(number: '7', label: '授權中的對接'),
                      ),
                      Expanded(
                        child: _AdminStat(
                          number: '0',
                          label: '可疑的存取',
                          last: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const AnsibleMonoLabel(
            '授權中 · GRANTS',
            padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
          ),
          AnsibleRuleGroup(
            children: [
              for (var i = 0; i < grants.length; i += 1)
                _GrantRow(grant: grants[i], last: i == grants.length - 1),
            ],
          ),
          const AnsibleMonoLabel(
            '近期存取 · LOG',
            padding: EdgeInsets.fromLTRB(22, 20, 22, 8),
          ),
          AnsibleRuleGroup(
            children: [
              for (var i = 0; i < events.length; i += 1)
                _AuditRow(event: events[i], last: i == events.length - 1),
            ],
          ),
          const AnsibleMonoLabel(
            '不可逆 · IRREVERSIBLE',
            padding: EdgeInsets.fromLTRB(22, 24, 22, 8),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 22),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: AnsibleDesign.danger, width: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Column(
              children: [
                _DangerRow(title: '撤銷所有非此裝置', sub: '其他裝置與圈會被踢出。可重新授權。'),
                Divider(color: AnsibleDesign.ruleSoft, height: 20),
                _DangerRow(
                  title: '焚燒此身分',
                  sub: '所有衍生身分一併消失。其他人裝置上的副本仍存在，但無法再驗證。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AdminStat extends StatelessWidget {
  const _AdminStat({
    required this.number,
    required this.label,
    this.last = false,
  });

  final String number;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          right: last
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          Text(
            number,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: AnsibleDesign.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
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

class _GrantRow extends StatelessWidget {
  const _GrantRow({required this.grant, required this.last});

  final _Grant grant;
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
          Row(
            children: [
              Text(
                grant.who,
                style: const TextStyle(fontSize: 14, color: AnsibleDesign.ink),
              ),
              const SizedBox(width: 8),
              Text(
                grant.whoEn,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 8.5,
                  letterSpacing: 1.4,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
              const Spacer(),
              Text(
                grant.when,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 9,
                  color: AnsibleDesign.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('用', style: TextStyle(color: AnsibleDesign.inkMuted)),
              Text(
                grant.what,
                style: const TextStyle(
                  color: AnsibleDesign.ink,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const Text('·', style: TextStyle(color: AnsibleDesign.inkFaint)),
              Text(
                grant.scope,
                style: const TextStyle(color: AnsibleDesign.inkMuted),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  '撤銷',
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1,
                    color: AnsibleDesign.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event, required this.last});

  final _AuditEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: last
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              event.who,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AnsibleDesign.ink),
            ),
          ),
          Expanded(
            child: Text(
              event.act,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.via,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 8.5,
              letterSpacing: 1,
              color: AnsibleDesign.inkFaint,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.when,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({required this.title, required this.sub});

  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.55,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(onPressed: null, child: Text('執行')),
      ],
    );
  }
}

class _Grant {
  const _Grant(this.who, this.whoEn, this.what, this.scope, this.when);

  final String who;
  final String whoEn;
  final String what;
  final String scope;
  final String when;
}

class _AuditEvent {
  const _AuditEvent(this.who, this.act, this.via, this.when);

  final String who;
  final String act;
  final String via;
  final String when;
}
