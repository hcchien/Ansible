import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../services/app_view_timeline_client.dart';
import '../theme/ansible_design.dart';

/// Renders curated external (fediverse) content for an external-inclusive board
/// in a clearly-separated, labeled section, visually DISTINCT from native
/// posts. Per the inbound-federation constitution review, every item carries a
/// visible origin (instance + actor handle) and a compliance badge, and is
/// never presented as verified / 真人 content.
///
/// The caller (board view) only builds this section after confirming BOTH
/// gates — board.externalInclusion AND the user opt-in — so this widget renders
/// whatever items it is given.
class ExternalContentSection extends StatelessWidget {
  const ExternalContentSection({super.key, required this.items});

  final List<AppViewExternalItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('external_content_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(),
        for (final item in items) _ExternalCard(item: item),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsibleDesign.rule, width: 0.8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, size: 16, color: AnsibleDesign.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.uiCopy(
                zh: '站外內容 · From the fediverse',
                en: 'From the fediverse · 站外內容',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                letterSpacing: 1.1,
                color: AnsibleDesign.inkFaint,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExternalCard extends StatelessWidget {
  const _ExternalCard({required this.item});

  final AppViewExternalItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('external_item_${item.opId}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AnsibleDesign.paperElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AnsibleDesign.rule, width: 0.6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    item.actorHandle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 11.5,
                      letterSpacing: 0.4,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _ComplianceBadge(item: item),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AnsibleDesign.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.uiCopy(
                zh: '站外·未驗證 · ${item.externalInstance}',
                en: 'External · unverified · ${item.externalInstance}',
              ),
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 9,
                letterSpacing: 0.8,
                color: AnsibleDesign.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compliance badge: `compatible` for assessed allowlisted instances, else
/// `unknown` (lower-trust signal). Always visible per Base Rule 6/7.
class _ComplianceBadge extends StatelessWidget {
  const _ComplianceBadge({required this.item});

  final AppViewExternalItem item;

  @override
  Widget build(BuildContext context) {
    final compatible = item.isCompatible;
    final color = compatible ? AnsibleDesign.spore : AnsibleDesign.inkFaint;
    final label = compatible
        ? context.uiCopy(zh: '相容', en: 'COMPATIBLE')
        : context.uiCopy(zh: '未評估', en: 'UNKNOWN');
    return Container(
      key: Key('external_compliance_${item.opId}'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 0.7),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 8.5,
          letterSpacing: 0.9,
          color: color,
        ),
      ),
    );
  }
}
