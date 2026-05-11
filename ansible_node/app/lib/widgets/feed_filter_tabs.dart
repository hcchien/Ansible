import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
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
    final l10n = context.l10n;
    return SegmentedButton<FeedFilter>(
      style: SegmentedButton.styleFrom(
        backgroundColor: AnsibleDesign.paper,
        selectedBackgroundColor: AnsibleDesign.paperDeep,
        foregroundColor: AnsibleDesign.inkMuted,
        selectedForegroundColor: AnsibleDesign.ink,
        side: const BorderSide(color: AnsibleDesign.rule, width: 0.5),
      ),
      segments: [
        ButtonSegment(value: FeedFilter.all, label: Text(l10n.feedAll)),
        ButtonSegment(
          value: FeedFilter.following,
          label: Text(l10n.feedFollowing),
        ),
        ButtonSegment(value: FeedFilter.boards, label: Text(l10n.feedBoards)),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}
