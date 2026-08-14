import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

class ReactionPickerResult {
  const ReactionPickerResult.select(this.type) : remove = false;

  const ReactionPickerResult.remove() : type = null, remove = true;

  final ReactionType? type;
  final bool remove;
}

const _reactionEmoji = {
  ReactionType.thumbsUp: '👍',
  ReactionType.happy: '😄',
  ReactionType.sad: '😢',
  ReactionType.angry: '😠',
};

String reactionEmoji(ReactionType? type) =>
    type == null ? '♡' : _reactionEmoji[type]!;

/// Shared adaptive picker for every Flutter target (web, mobile, desktop).
Future<ReactionPickerResult?> showReactionPicker(
  BuildContext context, {
  required ReactionType? selected,
}) {
  return showModalBottomSheet<ReactionPickerResult>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final type in ReactionType.values)
              ChoiceChip(
                label: Text(
                  _reactionEmoji[type]!,
                  style: const TextStyle(fontSize: 24),
                ),
                selected: type == selected,
                onSelected: (_) =>
                    Navigator.pop(context, ReactionPickerResult.select(type)),
              ),
            if (selected != null)
              TextButton.icon(
                onPressed: () =>
                    Navigator.pop(context, const ReactionPickerResult.remove()),
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('移除我的 reaction'),
              ),
          ],
        ),
      ),
    ),
  );
}
