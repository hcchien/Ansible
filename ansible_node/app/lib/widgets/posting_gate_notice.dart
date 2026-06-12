import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../screens/add_credential_screen.dart';
import '../theme/ansible_design.dart';

/// Explains a board's verified-human posting gate where the composer would
/// normally be, with a CTA into the credential issuance wizard.
///
/// Shown when the local user's reputation tier is below the board's
/// `posting_policy.min_post_tier`. The relay re-checks at acceptance time;
/// this notice is the "gate discoverable before posting" half of the contract.
class PostingGateNotice extends StatelessWidget {
  const PostingGateNotice({
    super.key,
    required this.localDid,
    this.onUpgradeCompleted,
  });

  /// The local user's DID, used as the credential holder for the upgrade flow.
  final String localDid;

  /// Called after returning from the credential wizard so callers can
  /// re-check the tier (the gate may have lifted).
  final VoidCallback? onUpgradeCompleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AnsibleDesign.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AnsibleDesign.accent.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined,
                  size: 18, color: AnsibleDesign.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.uiCopy(
                    zh: '此看板僅限通過真人驗證的成員發文',
                    en: 'Only verified humans can post in this board',
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AnsibleDesign.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            context.uiCopy(
              zh: '完成真人驗證後即可在此發文，閱讀不受影響。',
              en: 'Complete identity verification to post here. '
                  'Reading is not affected.',
            ),
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AnsibleDesign.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddCredentialScreen(
                    holderDid: localDid,
                    onCredentialAdded: (_) {},
                  ),
                ),
              );
              onUpgradeCompleted?.call();
            },
            icon: const Icon(Icons.upgrade, size: 16),
            label: Text(context.uiCopy(zh: '升級驗證', en: 'Upgrade verification')),
          ),
        ],
      ),
    );
  }
}
