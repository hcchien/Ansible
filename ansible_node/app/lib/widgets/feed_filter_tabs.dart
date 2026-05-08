import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

enum FeedFilter { all, following, boards }

class FeedFilterTabs extends StatelessWidget {
  const FeedFilterTabs({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final FeedFilter selected;
  final ValueChanged<FeedFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FeedFilter>(
      style: SegmentedButton.styleFrom(
        backgroundColor: AnsibleDesign.paper,
        selectedBackgroundColor: AnsibleDesign.paperDeep,
        foregroundColor: AnsibleDesign.inkMuted,
        selectedForegroundColor: AnsibleDesign.ink,
        side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
      ),
      segments: const [
        ButtonSegment(value: FeedFilter.all, label: Text('全部')),
        ButtonSegment(value: FeedFilter.following, label: Text('圈內')),
        ButtonSegment(value: FeedFilter.boards, label: Text('看板')),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}
