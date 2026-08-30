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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    final selectedBackground = dark
        ? AnsibleDesign.darkTintLavender
        : AnsibleDesign.tintLavender;
    final foreground = dark
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
    final selectedForeground = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    return SegmentedButton<FeedFilter>(
      style: SegmentedButton.styleFrom(
        backgroundColor: background,
        selectedBackgroundColor: selectedBackground,
        foregroundColor: foreground,
        selectedForegroundColor: selectedForeground,
        side: BorderSide(color: rule, width: 0.5),
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
