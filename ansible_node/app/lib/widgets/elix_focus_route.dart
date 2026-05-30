import 'dart:math' as math;

import 'package:flutter/material.dart';

Route<T> elixFocusPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final mediaQuery = MediaQuery.maybeOf(context);
      if (mediaQuery?.disableAnimations == true ||
          mediaQuery?.accessibleNavigation == true) {
        return child;
      }

      final enter = Curves.easeOutCubic.transform(animation.value);
      final exit = Curves.easeInCubic.transform(secondaryAnimation.value);
      final angle = ((1 - enter) * -math.pi / 18) + (exit * math.pi / 24);
      final dx = ((1 - enter) * 36) - (exit * 18);
      final opacity = (0.92 + (0.08 * enter)).clamp(0.0, 1.0).toDouble();

      return Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..translateByDouble(dx, 0, 0, 1)
          ..rotateY(angle),
        child: Opacity(opacity: opacity, child: child),
      );
    },
  );
}
