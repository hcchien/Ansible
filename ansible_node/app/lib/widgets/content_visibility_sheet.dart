import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

Future<ContentVisibility?> showContentVisibilitySheet({
  required BuildContext context,
  required ContentVisibility current,
  required String subjectLabel,
}) {
  var picked = current;
  return showModalBottomSheet<ContentVisibility>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AnsibleDesign.ink.withValues(alpha: 0.20),
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: AnsibleDesign.paper,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AnsibleDesign.ink.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      decoration: BoxDecoration(
                        color: AnsibleDesign.rule,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '誰能看見 · VISIBILITY',
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9.5,
                            color: AnsibleDesign.inkFaint,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$subjectLabel 給誰看？',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w500,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '之後也可以改。預設留在你這裡。',
                          style: TextStyle(
                            fontSize: 12,
                            color: AnsibleDesign.inkMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 0.5, color: AnsibleDesign.rule),
                  for (final option in _visibilityOptions)
                    _VisibilityOptionRow(
                      option: option,
                      selected: picked == option.visibility,
                      onTap: () =>
                          setSheetState(() => picked = option.visibility),
                    ),
                  const Divider(height: 0.5, color: AnsibleDesign.rule),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(picked),
                            child: const Text('確認'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

({String label, Color dot}) contentVisibilityMeta(
  ContentVisibility visibility,
) {
  return switch (visibility) {
    ContentVisibility.private => (
      label: 'PRIVATE',
      dot: AnsibleDesign.inkMuted,
    ),
    ContentVisibility.unlisted => (label: 'CIRCLE', dot: AnsibleDesign.spore),
    ContentVisibility.public => (label: 'PUBLIC', dot: AnsibleDesign.accent),
  };
}

class _VisibilityOptionRow extends StatelessWidget {
  const _VisibilityOptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _VisibilityOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AnsibleDesign.paperElev : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7),
              decoration: BoxDecoration(
                color: option.dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        option.zh,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AnsibleDesign.ink,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          option.en,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 9,
                            letterSpacing: 1.5,
                            color: AnsibleDesign.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                color: selected ? AnsibleDesign.ink : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AnsibleDesign.ink : AnsibleDesign.rule,
                  width: 0.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AnsibleDesign.paper,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityOption {
  const _VisibilityOption({
    required this.visibility,
    required this.zh,
    required this.en,
    required this.description,
    required this.dot,
  });

  final ContentVisibility visibility;
  final String zh;
  final String en;
  final String description;
  final Color dot;
}

const _visibilityOptions = [
  _VisibilityOption(
    visibility: ContentVisibility.private,
    zh: '留在本地',
    en: 'PRIVATE',
    description: '只有你看得見。連同步到別台也只有你的裝置。',
    dot: AnsibleDesign.inkMuted,
  ),
  _VisibilityOption(
    visibility: ContentVisibility.unlisted,
    zh: '送進讀書會',
    en: 'CIRCLE · 4 人',
    description: '圈內 4 人都能讀。可以再加，但離開的人讀不到新的。',
    dot: AnsibleDesign.spore,
  ),
  _VisibilityOption(
    visibility: ContentVisibility.public,
    zh: '公開',
    en: 'PUBLIC',
    description: '任何人都能讀。會出現在公開討論串裡。',
    dot: AnsibleDesign.accent,
  ),
];
