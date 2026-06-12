import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../services/network_status_service.dart';

class NetworkStatusIndicator extends StatelessWidget {
  const NetworkStatusIndicator({
    super.key,
    required this.status,
    required this.connectionType,
    this.compact = false,
    this.onTap,
  });

  final NetworkStatus status;
  final String connectionType;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    IconData icon;
    Color color;
    String tooltip;
    String label;

    switch (status) {
      case NetworkStatus.online:
        icon = Icons.wifi_rounded;
        color = Colors.green;
        label = connectionType;
        tooltip = '${l10n.networkOnline} · $connectionType';
        break;
      case NetworkStatus.offline:
        icon = Icons.wifi_off_rounded;
        color = Colors.red;
        label = l10n.networkOffline;
        tooltip = l10n.networkOffline;
        break;
      case NetworkStatus.checking:
        icon = Icons.wifi_find_rounded;
        color = Colors.orange;
        label = l10n.networkChecking;
        tooltip = l10n.networkChecking;
        break;
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: compact
              ? _NetworkStatusGlyph(icon: icon, color: color)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _NetworkStatusGlyph(icon: icon, color: color),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _NetworkStatusGlyph extends StatelessWidget {
  const _NetworkStatusGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: 16, color: color);
  }
}
