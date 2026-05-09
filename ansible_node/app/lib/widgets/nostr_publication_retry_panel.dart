import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

class NostrPublicationRetryPanel extends StatelessWidget {
  final List<PublicationTarget> failedTargets;
  final Future<void> Function(PublicationTarget target) onRetry;
  final Future<void> Function(PublicationTarget target) onReset;

  const NostrPublicationRetryPanel({
    super.key,
    required this.failedTargets,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    if (failedTargets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 20, 22, 8),
          child: Text(
            'Nostr 發佈待處理',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0,
              fontWeight: FontWeight.w600,
              color: AnsibleDesign.inkFaint,
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
              bottom: BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < failedTargets.length; i += 1)
                _FailedTargetRow(
                  target: failedTargets[i],
                  isLast: i == failedTargets.length - 1,
                  onRetry: onRetry,
                  onReset: onReset,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FailedTargetRow extends StatelessWidget {
  final PublicationTarget target;
  final bool isLast;
  final Future<void> Function(PublicationTarget target) onRetry;
  final Future<void> Function(PublicationTarget target) onReset;

  const _FailedTargetRow({
    required this.target,
    required this.isLast,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 14, 12),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              size: 18,
              color: AnsibleDesign.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target.endpoint,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AnsibleDesign.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (target.error != null && target.error!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      target.error!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              key: ValueKey('retry-${target.targetId}'),
              tooltip: '重試',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: () => onRetry(target),
            ),
            IconButton(
              key: ValueKey('reset-${target.targetId}'),
              tooltip: '重設',
              icon: const Icon(Icons.restart_alt, size: 18),
              onPressed: () => onReset(target),
            ),
          ],
        ),
      ),
    );
  }
}
