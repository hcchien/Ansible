import 'package:flutter/material.dart';
import 'package:ansible_store/ansible_store.dart';

/// A small inline badge showing the count of pending ops in the local queue.
///
/// Returns [SizedBox.shrink] when the count is zero so it takes no space.
/// Used in the TopBar to give the user a visual indicator of offline-queued
/// content that has not yet been relayed.
class OpsQueueStatusBadge extends StatelessWidget {
  final OpsQueueRepository repository;

  const OpsQueueStatusBadge({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OpsQueueEntry>>(
      stream: repository.watchOutstanding(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <OpsQueueEntry>[];
        final count = entries.length;
        final blocked = entries
            .where((entry) => entry.status == 'blocked')
            .length;
        if (count == 0) return const SizedBox.shrink();
        return Tooltip(
          message: blocked > 0
              ? '$blocked local post(s) are waiting for board permission'
              : '$count local change(s) are waiting to sync',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: blocked > 0 ? Colors.deepOrange.shade200 : Colors.amber,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      },
    );
  }
}
