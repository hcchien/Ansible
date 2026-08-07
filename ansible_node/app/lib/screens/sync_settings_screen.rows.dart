part of 'sync_settings_screen.dart';

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
          Theme(
            data: Theme.of(
              context,
            ).copyWith(switchTheme: AnsibleDesign.paperSwitchTheme()),
            child: Switch(value: on, onChanged: null),
          ),
        ],
      ),
    );
  }
}
