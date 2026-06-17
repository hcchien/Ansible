part of 'sync_settings_screen.dart';

enum _CircleSyncStatus { live, paused, behind }

class _EmptyCircleSyncRow extends StatelessWidget {
  const _EmptyCircleSyncRow();

  @override
  Widget build(BuildContext context) {
    final text = SubpageL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Text(
        text.t('noSyncedCircles'),
        style: const TextStyle(
          fontSize: 13,
          height: 1.6,
          color: AnsibleDesign.inkMuted,
        ),
      ),
    );
  }
}

class _CircleSyncRow extends StatelessWidget {
  const _CircleSyncRow({
    required this.name,
    required this.subtitle,
    required this.status,
  });

  final String name;
  final String subtitle;
  final _CircleSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _CircleSyncStatus.live => AnsibleDesign.spore,
      _CircleSyncStatus.paused => AnsibleDesign.rule,
      _CircleSyncStatus.behind => AnsibleDesign.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AnsibleDesign.paperDeep,
              border: Border.all(color: AnsibleDesign.rule, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Text(
              name.characters.first,
              style: const TextStyle(
                fontSize: 11,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }
}

class _SyncSwitchRow extends StatelessWidget {
  const _SyncSwitchRow({
    required this.label,
    required this.sub,
    required this.on,
    this.last = false,
  });

  final String label;
  final String sub;
  final bool on;
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: on, onChanged: null),
        ],
      ),
    );
  }
}
