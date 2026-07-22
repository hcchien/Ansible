import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../config/app_environment.dart';
import '../../l10n/app_l10n.dart';
import '../../services/app_locale_controller.dart';
import '../../services/discovery_client.dart';
import '../../services/messenger_sync_service.dart';
import '../../services/network_status_service.dart';
import '../../services/reading_preferences_controller.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/ops_queue_status_badge.dart';
import '../contact_picker_screen.dart' show ContactInputResolver;
import '../discover_screen.dart';
import '../inbox_screen.dart' show ContactAvailabilityResolver;
import '../search_screen.dart';
import '../settings_home_screen.dart';
import '../wallet_screen.dart';
import 'network_status_indicator.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({
    super.key,
    this.onClearIdentity,
    required this.db,
    required this.did,
    this.localeController,
    this.readingPreferencesController,
    required this.opsQueueRepo,
    required this.onSync,
    required this.syncing,
    required this.networkStatusService,
    required this.contentItems,
    required this.messengerSyncService,
    required this.contactAvailabilityResolver,
    required this.contactInputResolver,
    required this.hasActiveRelay,
    required this.screenStyle,
    required this.onScreenStyleTap,
    required this.screenStyleLabel,
    required this.personalScreenStyle,
    required this.forumScreenStyle,
    required this.boardMotion,
    required this.onPersonalScreenStyleChanged,
    required this.onForumScreenStyleChanged,
    required this.onBoardMotionChanged,
  });

  final VoidCallback? onClearIdentity;
  final AppDatabase db;
  final String did;
  final AppLocaleController? localeController;
  final ReadingPreferencesController? readingPreferencesController;
  final OpsQueueRepository opsQueueRepo;
  final Future<void> Function() onSync;
  final bool syncing;
  final NetworkStatusMonitor networkStatusService;
  final List<ContentItem> contentItems;
  final MessengerSyncService messengerSyncService;
  final ContactAvailabilityResolver contactAvailabilityResolver;
  final ContactInputResolver contactInputResolver;
  final bool hasActiveRelay;
  final ElixScreenStyle screenStyle;
  final VoidCallback onScreenStyleTap;
  final String screenStyleLabel;
  final ElixScreenStyle personalScreenStyle;
  final ElixScreenStyle forumScreenStyle;
  final ElixBoardMotion boardMotion;
  final ValueChanged<ElixScreenStyle> onPersonalScreenStyleChanged;
  final ValueChanged<ElixScreenStyle> onForumScreenStyleChanged;
  final ValueChanged<ElixBoardMotion> onBoardMotionChanged;

  String get _truncatedDid {
    if (did.length <= 24) return did;
    return '${did.substring(0, 18)}...${did.substring(did.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styleData = screenStyle.dataFor(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: styleData.background,
        border: Border(bottom: BorderSide(color: styleData.rule, width: 0.5)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;

          return Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnsibleMark(size: compact ? 34 : 38),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    const ElixWordmark(fontSize: 24),
                  ],
                ],
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: networkStatusService,
                builder: (context, _) {
                  return NetworkStatusIndicator(
                    status: networkStatusService.status,
                    connectionType: networkStatusService.connectionType,
                    compact: compact,
                    onTap: () => networkStatusService.checkStatus(),
                  );
                },
              ),
              SizedBox(width: compact ? 2 : 8),
              IconButton.filledTonal(
                key: const Key('home_discovery_button'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchScreen(db: db, localDid: did),
                    ),
                  );
                },
                icon: const Icon(Icons.search),
                color: styleData.muted,
                tooltip: l10n.search,
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DiscoverScreen(
                        db: db,
                        localDid: did,
                        client: DiscoveryClient(
                          appViewBaseUrl: AppEnvironment.appViewBaseUrl,
                          relayBaseUrl: AppEnvironment.defaultRelayBaseUrl,
                        ),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.explore_outlined),
                color: styleData.foreground,
                style: IconButton.styleFrom(
                  backgroundColor: AnsibleDesign.ochre.withValues(alpha: 0.18),
                  side: const BorderSide(
                    color: AnsibleDesign.ochre,
                    width: 0.7,
                  ),
                ),
                tooltip: context.uiCopy(zh: '探索', en: 'Discover'),
              ),
              IconButton(
                key: const Key('screen_style_button'),
                onPressed: onScreenStyleTap,
                icon: const Icon(Icons.palette_outlined),
                color: styleData.muted,
                tooltip: 'Screen style · $screenStyleLabel',
              ),
              IconButton(
                key: const Key('settings_button'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsHomeScreen(
                        db: db,
                        did: did,
                        localeController: localeController,
                        readingPreferencesController:
                            readingPreferencesController,
                        onClearIdentity: onClearIdentity,
                        personalScreenStyle: personalScreenStyle,
                        forumScreenStyle: forumScreenStyle,
                        boardMotion: boardMotion,
                        onPersonalScreenStyleChanged:
                            onPersonalScreenStyleChanged,
                        onForumScreenStyleChanged: onForumScreenStyleChanged,
                        onBoardMotionChanged: onBoardMotionChanged,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person_outline),
                color: styleData.muted,
                tooltip: l10n.settingsNav,
              ),
              if (!compact)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WalletScreen(
                          holderDid: did,
                          repository: DriftWalletRepository(db),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text(l10n.wallet),
                  style: TextButton.styleFrom(
                    foregroundColor: AnsibleDesign.paper,
                    backgroundColor: AnsibleDesign.ink,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              if (!compact) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AnsibleDesign.paperElev,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AnsibleDesign.rule, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ElixSignedPill(kind: 'PK'),
                      const SizedBox(width: 8),
                      Text(
                        _truncatedDid,
                        style: const TextStyle(
                          color: AnsibleDesign.inkMuted,
                          fontSize: 12,
                          fontFamily: AnsibleDesign.mono,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OpsQueueStatusBadge(repository: opsQueueRepo),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                onPressed: syncing ? null : onSync,
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                color: styleData.muted,
                tooltip: l10n.sync,
              ),
            ],
          );
        },
      ),
    );
  }
}
