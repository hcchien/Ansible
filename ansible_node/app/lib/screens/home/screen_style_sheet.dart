import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import '../../widgets/ansible_screen_chrome.dart';

class ScreenStyleSheet extends StatelessWidget {
  const ScreenStyleSheet({
    super.key,
    required this.personalStyle,
    required this.forumStyle,
    required this.motion,
    required this.onPersonalStyleSelected,
    required this.onForumStyleSelected,
    required this.onMotionSelected,
  });

  final ElixScreenStyle personalStyle;
  final ElixScreenStyle forumStyle;
  final ElixBoardMotion motion;
  final ValueChanged<ElixScreenStyle> onPersonalStyleSelected;
  final ValueChanged<ElixScreenStyle> onForumStyleSelected;
  final ValueChanged<ElixBoardMotion> onMotionSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AnsibleDesign.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.uiCopy(zh: '介面與語言', en: 'Interface & Language'),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AnsibleDesign.ink,
                ),
              ),
              const SizedBox(height: 14),
              AnsibleMonoLabel(context.uiCopy(zh: '每版的光', en: 'BOARD THEME')),
              const SizedBox(height: 8),
              Text(
                context.uiCopy(
                  zh: '每個版可以有自己的光。Swipe 換版時，顏色也會跟著換。',
                  en: 'Each board can have its own theme. Colors follow when you swipe between boards.',
                ),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 13,
                  height: 1.65,
                  color: AnsibleDesign.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              _BoardAtmosphereCard(
                boardLabel: context.uiCopy(zh: '個人版', en: 'Personal'),
                boardMeta: context.uiCopy(zh: '寫給自己', en: 'For yourself'),
                selected: personalStyle,
                keyPrefix: 'feed',
                onSelected: onPersonalStyleSelected,
              ),
              const SizedBox(height: 10),
              _BoardAtmosphereCard(
                boardLabel: context.uiCopy(zh: '討論區', en: 'Forum'),
                boardMeta: context.uiCopy(zh: '白天的廣場', en: 'Daylight square'),
                selected: forumStyle,
                keyPrefix: 'circle',
                onSelected: onForumStyleSelected,
              ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: AnsibleDesign.paperElev,
                  border: Border(
                    left: BorderSide(color: AnsibleDesign.ochre, width: 2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Text(
                    context.uiCopy(
                      zh: '不開放選別的顏色。寫過的東西仍是同一個品牌，只是換了一面光。',
                      en: 'Custom colors are not available. Your writing stays in the same brand, with a different light.',
                    ),
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 12,
                      height: 1.65,
                      color: AnsibleDesign.inkMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AnsibleMonoLabel(context.uiCopy(zh: '換版的動態', en: 'BOARD MOTION')),
              const SizedBox(height: 8),
              Text(
                context.uiCopy(
                  zh: '如果系統開了「減少動態」，Elix 會自動降回平移。',
                  en: 'When Reduce Motion is enabled, Elix automatically falls back to slide.',
                ),
                style: const TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 13,
                  height: 1.65,
                  color: AnsibleDesign.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 12),
              _MotionOption(
                key: const Key('board_motion_slide'),
                title: context.uiCopy(zh: 'Slide · 平移', en: 'Slide'),
                subtitle: context.uiCopy(
                  zh: '兩張紙左右平移，沒有立體感。',
                  en: 'Two pages slide side to side with no 3D effect.',
                ),
                selected: motion == ElixBoardMotion.slide,
                onTap: () => onMotionSelected(ElixBoardMotion.slide),
              ),
              _MotionOption(
                key: const Key('board_motion_book'),
                title: context.uiCopy(zh: 'Book · 翻書', en: 'Book'),
                badge: context.uiCopy(zh: '預設', en: 'Default'),
                subtitle: context.uiCopy(
                  zh: '兩個版像書的左右頁，輕微 perspective。',
                  en: 'Boards turn like left and right pages with light perspective.',
                ),
                selected: motion == ElixBoardMotion.book,
                onTap: () => onMotionSelected(ElixBoardMotion.book),
              ),
              _MotionOption(
                key: const Key('board_motion_cube'),
                title: context.uiCopy(zh: 'Cube · 翻立方', en: 'Cube'),
                subtitle: context.uiCopy(
                  zh: '較完整的 rotateY，切換感更強。',
                  en: 'Fuller rotateY motion with a stronger switch feel.',
                ),
                selected: motion == ElixBoardMotion.cube,
                onTap: () => onMotionSelected(ElixBoardMotion.cube),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardAtmosphereCard extends StatelessWidget {
  const _BoardAtmosphereCard({
    required this.boardLabel,
    required this.boardMeta,
    required this.selected,
    required this.keyPrefix,
    required this.onSelected,
  });

  final String boardLabel;
  final String boardMeta;
  final ElixScreenStyle selected;
  final String keyPrefix;
  final ValueChanged<ElixScreenStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsibleDesign.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
      ),
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            Row(
              children: [
                if (keyPrefix == 'feed') ...[
                  const AnsibleMark(size: 13),
                  const SizedBox(width: 8),
                ] else ...[
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AnsibleDesign.ink, width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  boardLabel,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.serif,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AnsibleDesign.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  boardMeta,
                  style: const TextStyle(
                    fontFamily: AnsibleDesign.mono,
                    fontSize: 9,
                    letterSpacing: 1.1,
                    color: AnsibleDesign.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final style in ElixScreenStyle.values) ...[
                  Expanded(
                    child: _ScreenStyleSwatch(
                      key: Key(
                        'screen_style_choice_${keyPrefix}_${style.name}',
                      ),
                      style: style,
                      selected: selected == style,
                      onTap: () => onSelected(style),
                    ),
                  ),
                  if (style != ElixScreenStyle.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenStyleSwatch extends StatelessWidget {
  const _ScreenStyleSwatch({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final ElixScreenStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.paperElev : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            _StylePreview(style: style),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.circle_outlined,
                  size: 10,
                  color: selected
                      ? AnsibleDesign.ochre
                      : AnsibleDesign.inkFaint,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    context.uiCopy(zh: style.zhLabel, en: style.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: selected
                          ? AnsibleDesign.ink
                          : AnsibleDesign.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.style});

  final ElixScreenStyle style;

  @override
  Widget build(BuildContext context) {
    final data = style.dataFor(Theme.of(context).brightness);
    final decoration = style == ElixScreenStyle.system
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0.5, 0.5],
              colors: [AnsibleDesign.paper, AnsibleDesign.darkPaper],
            ),
          )
        : BoxDecoration(
            color: data.background,
            borderRadius: BorderRadius.circular(5),
          );
    final lineColor = style == ElixScreenStyle.ink
        ? AnsibleDesign.darkInk
        : AnsibleDesign.ink;
    final mutedLine = style == ElixScreenStyle.ink
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
    final dotColor = style == ElixScreenStyle.ink
        ? AnsibleDesign.darkOchre
        : AnsibleDesign.ochre;

    return Container(
      height: 48,
      decoration: decoration,
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              width: 18,
              height: 1.5,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            top: 14,
            left: 8,
            child: Container(
              width: 28,
              height: 1.5,
              decoration: BoxDecoration(
                color: mutedLine,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Positioned(
            right: 7,
            bottom: 7,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MotionOption extends StatelessWidget {
  const _MotionOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AnsibleDesign.paperElev : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AnsibleDesign.ochre : AnsibleDesign.rule,
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.circle_outlined,
              size: 16,
              color: selected ? AnsibleDesign.ochre : AnsibleDesign.inkFaint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: AnsibleDesign.serif,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AnsibleDesign.ink,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AnsibleDesign.ochre,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontFamily: AnsibleDesign.mono,
                              fontSize: 11,
                              letterSpacing: 1.1,
                              color: AnsibleDesign.ochre,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: AnsibleDesign.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
