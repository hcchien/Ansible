import 'package:flutter/material.dart';

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
      segments: const [
        ButtonSegment(value: FeedFilter.all, label: Text('All')),
        ButtonSegment(value: FeedFilter.following, label: Text('Following')),
        ButtonSegment(value: FeedFilter.boards, label: Text('Boards')),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}
