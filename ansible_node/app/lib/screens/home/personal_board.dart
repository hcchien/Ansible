import 'package:ansible_store/ansible_store.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../services/relay_discovery_client.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import 'first_run_discovery.dart';
import 'home_types.dart';

/// Personal board (個人版) — A·01 spec.
class PersonalBoardView extends StatelessWidget {
  const PersonalBoardView({
    super.key,
    required this.loading,
    required this.contentItems,
    required this.personalFilter,
    required this.showFirstRunDiscovery,
    required this.firstRunDiscovery,
    required this.firstRunDiscoveryLoading,
    required this.onOpenDiscoveredForumHost,
    required this.onOpenCircle,
    required this.onStartAiAction,
    required this.onComposeTap,
  });

  final bool loading;
  final List<ContentItem> contentItems;
  final PersonalFilter personalFilter;
  final bool showFirstRunDiscovery;
  final RelayDiscovery? firstRunDiscovery;
  final bool firstRunDiscoveryLoading;
  final ValueChanged<String> onOpenDiscoveredForumHost;
  final void Function(BuildContext, CircleTab) onOpenCircle;
  final Future<void> Function() onStartAiAction;
  final VoidCallback onComposeTap;

  @override
  Widget build(BuildContext context) {
    final styleData = ElixScreenStyleScope.dataOf(context);
    final fgColor = styleData.foreground;
    final mutedColor = styleData.muted;
    final faintColor = styleData.faint;
    final bgSoftColor = styleData.surface;
    final borderSoft = styleData.rule;
    final emberColor = AnsibleDesign.ember;

    // A·01 time-ago formatting — matches design's "昨 14:36 / 前天 / MM.DD" style
    String timeAgo(DateTime dt) {
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) {
        return context.uiCopy(zh: '剛剛', en: 'just now');
      }
      if (diff.inDays < 1) {
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return diff.inHours < 1
            ? '${diff.inMinutes}m'
            : context.uiCopy(zh: '今 $hh:$mm', en: 'today $hh:$mm');
      }
      if (diff.inDays == 1) {
        final hh = dt.hour.toString().padLeft(2, '0');
        final mm = dt.minute.toString().padLeft(2, '0');
        return context.uiCopy(zh: '昨 $hh:$mm', en: 'yesterday $hh:$mm');
      }
      if (diff.inDays == 2) return context.uiCopy(zh: '前天', en: '2d ago');
      if (diff.inDays < 7) {
        return context.uiCopy(
          zh: '${diff.inDays} 天前',
          en: '${diff.inDays}d ago',
        );
      }
      return '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    }

    final filteredItems = switch (personalFilter) {
      PersonalFilter.all => contentItems,
      PersonalFilter.murmur =>
        contentItems.where((item) => item.mode == ContentMode.murmur).toList(),
      PersonalFilter.note =>
        contentItems.where((item) => item.mode == ContentMode.note).toList(),
    };
    final allSorted = [...filteredItems]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Split into this-week and earlier
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartDay = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );
    final thisWeek = allSorted
        .where((i) => i.createdAt.isAfter(weekStartDay))
        .toList();
    final earlier = allSorted
        .where((i) => !i.createdAt.isAfter(weekStartDay))
        .toList();

    // ── diary entry card (A·01 style) ──
    // Shows: pip + type-label + time on top row, then title (for notes), then italic preview
    Widget diaryCard(ContentItem item) {
      final isNote = item.mode == ContentMode.note;
      final pipColor = isNote ? fgColor : emberColor;
      final typeLabel = isNote ? 'NOTE' : 'MURMUR';

      return GestureDetector(
        onTap: () {
          onOpenCircle(context, isNote ? CircleTab.notes : CircleTab.murmur);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: styleData.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderSoft, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Meta row: pip · TYPE · time
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pipColor,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    typeLabel,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 8.5,
                      letterSpacing: 1.4,
                      color: faintColor,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeAgo(item.createdAt),
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 8.5,
                      letterSpacing: 0.5,
                      color: faintColor,
                    ),
                  ),
                ],
              ),
              // Title — only for notes
              if (isNote && item.title != null && item.title!.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  item.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: fgColor,
                    height: 1.3,
                  ),
                ),
              ],
              // Preview body
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 13,
                    color: mutedColor,
                    fontStyle: isNote ? FontStyle.normal : FontStyle.italic,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ── section kicker ──
    Widget sectionKicker(String zh, String en) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            Text(
              zh,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                letterSpacing: 1.4,
                color: faintColor,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· $en',
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                letterSpacing: 1.4,
                color: faintColor,
              ),
            ),
          ],
        ),
      );
    }

    Widget aiBridge() {
      return InkWell(
        key: const Key('home_ai_bridge'),
        onTap: onStartAiAction,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: bgSoftColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderSoft, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 38,
                decoration: BoxDecoration(
                  color: styleData.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 11),
              AnsibleMark(size: 18, color: fgColor),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.uiCopy(zh: 'AI · 橫向橋', en: 'AI · BRIDGE'),
                      style: TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 11,
                        letterSpacing: 1.3,
                        color: styleData.accent,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.uiCopy(
                        zh: '從本機 murmur 找材料，替筆記接出下一段。',
                        en: 'Find local murmurs and extend the next paragraph.',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        height: 1.35,
                        color: mutedColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: faintColor),
            ],
          ),
        ),
      );
    }

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            aiBridge(),
            const SizedBox(height: 14),
            FirstRunDiscoverySection(
              showFirstRunDiscovery: showFirstRunDiscovery,
              firstRunDiscovery: firstRunDiscovery,
              firstRunDiscoveryLoading: firstRunDiscoveryLoading,
              onOpenDiscoveredForumHost: onOpenDiscoveredForumHost,
            ),

            // ── This week section ────────────────────────────────────────
            if (thisWeek.isNotEmpty) ...[
              sectionKicker(
                context.uiCopy(zh: '本週', en: 'This week'),
                'THIS WEEK',
              ),
              ...thisWeek.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: diaryCard(item),
                ),
              ),
            ],

            // ── Earlier section ──────────────────────────────────────────
            if (earlier.isNotEmpty) ...[
              sectionKicker(
                context.uiCopy(zh: '上週', en: 'Earlier'),
                context.uiCopy(zh: '更早', en: 'OLDER'),
              ),
              ...earlier.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: diaryCard(item),
                ),
              ),
            ],

            // ── Empty state ──────────────────────────────────────────────
            if (allSorted.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    context.uiCopy(zh: '還沒有任何記錄', en: 'No entries yet'),
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 15,
                      color: faintColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ),

        // ── Floating AI dot (A·01 bottom-right, 56×56) ──
        Positioned(
          right: 0,
          bottom: 92,
          child: FloatingActionButton.small(
            key: const Key('home_compose_button'),
            heroTag: 'home_compose_button',
            onPressed: onComposeTap,
            backgroundColor: styleData.accent,
            foregroundColor: styleData.background,
            elevation: 0,
            tooltip: context.uiCopy(
              zh: '新增 Note 或 Murmur',
              en: 'New Note or Murmur',
            ),
            child: const Icon(Icons.add),
          ),
        ),

        Positioned(
          right: 0,
          bottom: 24,
          child: ElixAIDot(
            key: const Key('home_ai_button'),
            onTap: onStartAiAction,
          ),
        ),
      ],
    );
  }
}
