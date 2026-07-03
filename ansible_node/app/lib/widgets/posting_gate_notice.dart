import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../screens/add_credential_screen.dart';
import '../services/issuer_readiness_probe.dart';
import '../theme/ansible_design.dart';

/// Explains a board's verified-human posting gate where the composer would
/// normally be, with a CTA into the credential issuance wizard.
///
/// Shown when the local user's reputation tier is below the board's
/// `posting_policy.min_post_tier`. The relay re-checks at acceptance time;
/// this notice is the "gate discoverable before posting" half of the contract.
///
/// The CTA is gated on the issuer actually being able to issue (UX review
/// P1): while the production TW provider is fail-closed, the button shows an
/// honest 「即將開放」 state instead of a wizard that cannot finish.
class PostingGateNotice extends StatelessWidget {
  const PostingGateNotice({
    super.key,
    required this.localDid,
    this.onUpgradeCompleted,
    IssuerReadinessProbe? issuerProbe,
  }) : _issuerProbe = issuerProbe;

  /// The local user's DID, used as the credential holder for the upgrade flow.
  final String localDid;

  /// Called after returning from the credential wizard so callers can
  /// re-check the tier (the gate may have lifted).
  final VoidCallback? onUpgradeCompleted;

  /// Injectable for tests; defaults to the shared process-wide probe.
  final IssuerReadinessProbe? _issuerProbe;

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
          FutureBuilder<bool>(
            future: (_issuerProbe ?? IssuerReadinessProbe.shared).isReady(),
            builder: (context, snapshot) {
              // While probing, keep the disabled shape so nothing jumps.
              final ready = snapshot.data ?? false;
              if (!ready) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilledButton.icon(
                      key: const Key('posting_gate_coming_soon'),
                      onPressed: null,
                      icon: const Icon(Icons.schedule, size: 16),
                      label: Text(
                        context.uiCopy(
                          zh: '真人驗證即將開放',
                          en: 'Verification coming soon',
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.uiCopy(
                        zh: '驗證服務尚未開通。開放後即可在這裡完成升級。',
                        en: 'The verification service is not live yet. '
                            'You can upgrade here once it opens.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  ],
                );
              }
              return FilledButton.icon(
                key: const Key('posting_gate_upgrade'),
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
                label: Text(
                  context.uiCopy(zh: '升級驗證', en: 'Upgrade verification'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
