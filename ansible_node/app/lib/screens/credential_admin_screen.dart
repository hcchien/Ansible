import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../l10n/subpage_l10n.dart';
import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class CredentialAdminScreen extends StatelessWidget {
  const CredentialAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const grants = <_Grant>[];
    const events = <_AuditEvent>[];
    final text = SubpageL10n.of(context);

    return AnsibleScreenScaffold(
      title: context.uiCopy(zh: '存取與審計', en: 'Access & audit'),
      leadingLabel: text.t('backSettings'),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnsibleMonoLabel(text.t('adminLabel')),
                const SizedBox(height: 6),
                Text(
                  text.t('adminHero'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text.t('adminHeroSub'),
                  style: const TextStyle(
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
                  child: Row(
                    children: [
                      Expanded(
                        child: _AdminStat(
                          number: '0',
                          label: text.t('activeCircles'),
                        ),
                      ),
                      Expanded(
                        child: _AdminStat(
                          number: '${grants.length}',
                          label: text.t('activeGrants'),
                        ),
                      ),
                      Expanded(
                        child: _AdminStat(
                          number: '0',
                          label: text.t('suspiciousAccess'),
                          last: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AnsibleMonoLabel(
            text.t('grantsLabel'),
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          ),
          AnsibleRuleGroup(
            children: [
              if (grants.isEmpty)
                _EmptyAdminRow(text.t('noGrantLogs'))
              else
                for (var i = 0; i < grants.length; i += 1)
                  _GrantRow(grant: grants[i], last: i == grants.length - 1),
            ],
          ),
          AnsibleMonoLabel(
            text.t('accessLogLabel'),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
          ),
          AnsibleRuleGroup(
            children: [
              if (events.isEmpty)
                _EmptyAdminRow(text.t('noAccessLogs'))
              else
                for (var i = 0; i < events.length; i += 1)
                  _AuditRow(event: events[i], last: i == events.length - 1),
            ],
          ),
          AnsibleMonoLabel(
            text.t('irreversibleLabel'),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 8),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 22),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: AnsibleDesign.danger, width: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                _DangerRow(
                  title: text.t('revokeOtherDevices'),
                  sub: text.t('revokeOtherDevicesSub'),
                ),
                const Divider(color: AnsibleDesign.ruleSoft, height: 20),
                _DangerRow(
                  title: text.t('burnIdentity'),
                  sub: text.t('burnIdentitySub'),
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

class _EmptyAdminRow extends StatelessWidget {
  const _EmptyAdminRow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.6,
          color: AnsibleDesign.inkMuted,
        ),
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
              Text(
                SubpageL10n.of(context).t('grantUses'),
                style: const TextStyle(color: AnsibleDesign.inkMuted),
              ),
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
                child: Text(
                  SubpageL10n.of(context).t('revoke'),
                  style: const TextStyle(
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
        OutlinedButton(
          onPressed: null,
          child: Text(SubpageL10n.of(context).t('execute')),
        ),
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
