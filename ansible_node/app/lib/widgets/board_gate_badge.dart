import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';

/// Small chip shown next to a board title when the board only accepts posts
/// from verified humans (`posting_policy.min_post_tier == "verified_human"`).
///
/// Surfaces the gate *before* the user opens the composer, per the
/// constitution requirement that posting requirements be discoverable.
class BoardGateBadge extends StatelessWidget {
  const BoardGateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AnsibleDesign.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AnsibleDesign.accent.withValues(alpha: 0.55),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 11, color: AnsibleDesign.accent),
          const SizedBox(width: 3),
          Text(
            context.uiCopy(zh: '真人版', en: 'Verified only'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AnsibleDesign.accent,
            ),
          ),
        ],
      ),
    );
  }
}
