import 'package:flutter/material.dart';

import '../../l10n/subpage_l10n.dart';
import '../../services/relay_discovery_client.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/ansible_screen_chrome.dart';

/// First-run relay discovery block (announcements + starter boards) shown at
/// the top of the personal board until the user has local content.
class FirstRunDiscoverySection extends StatelessWidget {
  const FirstRunDiscoverySection({
    super.key,
    required this.showFirstRunDiscovery,
    required this.firstRunDiscovery,
    required this.firstRunDiscoveryLoading,
    required this.onOpenDiscoveredForumHost,
  });

  final bool showFirstRunDiscovery;
  final RelayDiscovery? firstRunDiscovery;
  final bool firstRunDiscoveryLoading;
  final ValueChanged<String> onOpenDiscoveredForumHost;

  @override
  Widget build(BuildContext context) {
    if (!showFirstRunDiscovery) return const SizedBox.shrink();
    final discovery = firstRunDiscovery;
    if (discovery == null && !firstRunDiscoveryLoading) {
      return const SizedBox.shrink();
    }
    final announcements =
        discovery?.announcements ?? const <RelayAnnouncement>[];
    final starterBoards =
        discovery?.featuredBoards ?? const <DiscoveredBoard>[];
    final hostComplianceByUrl = {
      for (final host
          in discovery?.featuredForumHosts ?? const <DiscoveredForumHost>[])
        host.forumHostUrl: host.constitutionCompliance,
    };
    if (discovery != null && announcements.isEmpty && starterBoards.isEmpty) {
      return const SizedBox.shrink();
    }

    final styleData = ElixScreenStyleScope.dataOf(context);
    final text = SubpageL10n.of(context);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: AnsibleMonoLabel(text.t('forumHosts')),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: styleData.surface.withValues(alpha: 0.55),
          border: Border(
            top: BorderSide(color: styleData.rule, width: 0.5),
            bottom: BorderSide(color: styleData.rule, width: 0.5),
          ),
        ),
        child: Column(
          children: [
            if (firstRunDiscoveryLoading && discovery == null)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            for (final announcement in announcements)
              _FirstRunDiscoveryRow(
                icon: Icons.campaign_outlined,
                title: announcement.title,
                subtitle: announcement.body,
                ruleColor: styleData.rule,
              ),
            for (final board in starterBoards)
              _FirstRunDiscoveryRow(
                icon: Icons.forum_outlined,
                title: board.title,
                subtitle: board.description ?? board.forumHostUrl,
                ruleColor: styleData.rule,
                compliance: _starterBoardCompliance(board, hostComplianceByUrl),
                action: OutlinedButton.icon(
                  onPressed: () =>
                      onOpenDiscoveredForumHost(board.forumHostUrl),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    text.t('addForumHost'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  String _starterBoardCompliance(
    DiscoveredBoard board,
    Map<String, String> hostComplianceByUrl,
  ) {
    final boardCompliance = board.constitutionCompliance.trim();
    if (boardCompliance.isNotEmpty) return boardCompliance;
    final hostCompliance = hostComplianceByUrl[board.forumHostUrl]?.trim();
    if (hostCompliance != null && hostCompliance.isNotEmpty) {
      return hostCompliance;
    }
    return 'unknown';
  }
}

class _FirstRunDiscoveryRow extends StatelessWidget {
  const _FirstRunDiscoveryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ruleColor,
    this.compliance,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color ruleColor;
  final String? compliance;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final styleData = ElixScreenStyleScope.dataOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ruleColor, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: styleData.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: styleData.foreground,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 12.5,
                      height: 1.35,
                      color: styleData.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (compliance != null) ...[
            const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: styleData.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ruleColor, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  compliance!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 0.6,
                    color: styleData.faint,
                  ),
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: action!,
            ),
          ],
        ],
      ),
    );
  }
}
