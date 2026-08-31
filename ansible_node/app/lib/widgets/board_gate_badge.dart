import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Small chip shown next to a board title when the board only accepts posts
/// from verified humans (`posting_policy.min_post_tier == "verified_human"`).
///
/// Surfaces the gate *before* the user opens the composer, per the
/// constitution requirement that posting requirements be discoverable.
class BoardGateBadge extends StatelessWidget {
  const BoardGateBadge({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('board_gate_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AnsibleDesign.highlight.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AnsibleDesign.highlight, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 11, color: AnsibleDesign.highlight),
          const SizedBox(width: 3),
          Text(
            label ?? context.uiCopy(zh: '真人版', en: 'Verified only'),
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AnsibleDesign.highlight,
            ),
          ),
        ],
      ),
    );
  }
}
