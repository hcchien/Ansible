import 'package:flutter/material.dart';

import '../../l10n/app_l10n.dart';
import '../../theme/ansible_design.dart';
import '../../theme/elix_screen_style.dart';
import 'home_types.dart';

double boardPageValue(PageController controller, double fallback) {
  if (!controller.hasClients) return fallback;
  final position = controller.position;
  if (!position.hasContentDimensions) return fallback;
  return controller.page ?? fallback;
}

class BoardFlipPage extends StatelessWidget {
  const BoardFlipPage({
    super.key,
    required this.pageController,
    required this.pageIndex,
    required this.selectedBoard,
    required this.motion,
    required this.child,
  });

  final PageController pageController;
  final int pageIndex;
  final HomeBoard selectedBoard;
  final ElixBoardMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      child: child,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final reduceMotion =
            media.disableAnimations || media.accessibleNavigation;
        final currentPage = boardPageValue(
          pageController,
          selectedBoard.index.toDouble(),
        );
        final delta = (currentPage - pageIndex).clamp(-1.0, 1.0).toDouble();
        final depth = delta.abs();
        final matrix = Matrix4.identity();
        if (reduceMotion || motion == ElixBoardMotion.slide) {
          matrix.translateByDouble(-delta * 10.0, 0.0, 0.0, 1.0);
        } else if (motion == ElixBoardMotion.book) {
          matrix
            ..setEntry(3, 2, 0.0012)
            ..translateByDouble(-delta * 28.0, 0.0, 0.0, 1.0)
            ..rotateY(-delta * 0.56);
        } else {
          matrix
            ..setEntry(3, 2, 0.0018)
            ..translateByDouble(-delta * 44.0, 0.0, 0.0, 1.0)
            ..rotateY(-delta * 1.18);
        }

        final hinge = delta >= 0 ? Alignment.centerLeft : Alignment.centerRight;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final shadeColor = dark
            ? Colors.black.withValues(alpha: 0.34)
            : AnsibleDesign.ink.withValues(alpha: 0.20);
        final spineColor = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;

        return Transform(
          alignment: hinge,
          transform: matrix,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (!reduceMotion &&
                  motion != ElixBoardMotion.slide &&
                  depth > 0.01)
                IgnorePointer(
                  child: Opacity(
                    opacity: depth.clamp(0.0, 0.82).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: delta >= 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          end: delta >= 0
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          colors: [Colors.transparent, shadeColor],
                          stops: const [0.34, 1.0],
                        ),
                        border: Border(
                          right: delta >= 0
                              ? BorderSide(color: spineColor, width: 0.5)
                              : BorderSide.none,
                          left: delta < 0
                              ? BorderSide(color: spineColor, width: 0.5)
                              : BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class BoardSwipeProgressPill extends StatelessWidget {
  const BoardSwipeProgressPill({
    super.key,
    required this.pageController,
    required this.compact,
    required this.motion,
  });

  final PageController pageController;
  final bool compact;
  final ElixBoardMotion motion;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        final maxIndex = HomeBoard.values.length - 1;
        final page = boardPageValue(
          pageController,
          0.0,
        ).clamp(0.0, maxIndex.toDouble()).toDouble();
        final lo = page.floor().clamp(0, maxIndex);
        final hi = page.ceil().clamp(0, maxIndex);
        final fractional = page - lo;
        final distanceFromEdge = fractional <= 0.5
            ? fractional
            : 1.0 - fractional;
        if (lo == hi || distanceFromEdge < 0.035) {
          return const SizedBox.shrink();
        }

        final currentIsLo = fractional < 0.5;
        final targetIndex = currentIsLo ? hi : lo;
        String boardName(int i) => switch (HomeBoard.values[i]) {
          HomeBoard.personal => context.uiCopy(zh: '個人版', en: 'Personal'),
          HomeBoard.timeline => context.uiCopy(zh: '時間軸', en: 'Timeline'),
          HomeBoard.forum => context.uiCopy(zh: '討論區', en: 'Forum'),
        };
        final switchTo = context.uiCopy(zh: '換到', en: 'Switch to');
        final targetLabel = '$switchTo ${boardName(targetIndex)}';
        final progress = currentIsLo ? fractional : 1.0 - fractional;
        final percent = (progress.clamp(0.0, 1.0) * 100).round();
        final dark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = dark
            ? AnsibleDesign.darkPaperElev
            : AnsibleDesign.paper;
        final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;

        return Positioned(
          left: 0,
          right: 0,
          bottom: compact ? 18 : 26,
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ochreColor, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        currentIsLo
                            ? Icons.chevron_right_rounded
                            : Icons.chevron_left_rounded,
                        size: 15,
                        color: ochreColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          motion == ElixBoardMotion.book
                              ? '$targetLabel · $percent%'
                              : targetLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AnsibleDesign.mono,
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: ochreColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
