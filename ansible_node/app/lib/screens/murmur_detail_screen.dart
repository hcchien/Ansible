import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';
import '../widgets/ansible_screen_chrome.dart';

class MurmurDetailScreen extends StatelessWidget {
  const MurmurDetailScreen({
    super.key,
    required this.murmur,
    this.contentItemRepository,
    this.onDeleted,
  });

  final ContentItem murmur;
  final ContentItemRepository? contentItemRepository;
  final Future<void> Function()? onDeleted;

  @override
  Widget build(BuildContext context) {
    return AnsibleScreenScaffold(
      title: 'MURMUR',
      leadingLabel: '← 草地',
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz),
        tooltip: '更多',
        onSelected: (value) {
          if (value == 'delete') {
            _confirmDelete(context);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'delete',
            enabled: contentItemRepository != null,
            child: const Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AnsibleDesign.danger,
                ),
                SizedBox(width: 10),
                Text('刪除碎念', style: TextStyle(color: AnsibleDesign.danger)),
              ],
            ),
          ),
        ],
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
                  children: [_Meta('${murmur.body.characters.length} 字')],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final repository = contentItemRepository;
    if (repository == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除碎念？'),
        content: const Text('這會把這則碎念從本機列表移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await repository.delete(murmur.id);
    await onDeleted?.call();
    if (!context.mounted) return;
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('已刪除碎念')));
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}·${local.month.toString().padLeft(2, '0')}·${local.day.toString().padLeft(2, '0')} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  static String _visibilityLabel(ContentVisibility visibility) {
    return switch (visibility) {
      ContentVisibility.private => 'private',
      ContentVisibility.unlisted => 'unlisted',
      ContentVisibility.public => 'public',
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
