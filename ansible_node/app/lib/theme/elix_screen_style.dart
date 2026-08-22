import 'package:flutter/material.dart';

import 'ansible_design.dart';

enum ElixScreenStyle {
  paper,
  ink,
  system;

  /// The app-wide appearance is authoritative when a screen is pushed from a
  /// route which is outside a board's own widget tree. This prevents the same
  /// board from silently falling back to Paper when opened through search,
  /// notifications, or a content link.
  static ElixScreenStyle forAppBrightness(Brightness brightness) =>
      brightness == Brightness.dark
      ? ElixScreenStyle.ink
      : ElixScreenStyle.paper;
}

enum ElixBoardMotion { slide, book, cube }

extension ElixScreenStyleUi on ElixScreenStyle {
  String get storageValue => name;

  String get label {
    switch (this) {
      case ElixScreenStyle.paper:
        return 'Paper';
      case ElixScreenStyle.ink:
        return 'Ink';
      case ElixScreenStyle.system:
        return 'Auto';
    }
  }

  String get zhLabel {
    switch (this) {
      case ElixScreenStyle.paper:
        return 'Paper';
      case ElixScreenStyle.ink:
        return 'Ink';
      case ElixScreenStyle.system:
        return 'Auto';
    }
  }

  String get description {
    switch (this) {
      case ElixScreenStyle.paper:
        return 'Daylight square';
      case ElixScreenStyle.ink:
        return 'Writing alone at night';
      case ElixScreenStyle.system:
        return 'Follows system appearance';
    }
  }

  ElixScreenStyleData get data => dataFor(Brightness.light);

  ElixScreenStyleData dataFor(Brightness brightness) {
    switch (this) {
      case ElixScreenStyle.paper:
        return const ElixScreenStyleData(
          background: AnsibleDesign.paper,
          surface: AnsibleDesign.paperElev,
          foreground: AnsibleDesign.ink,
          muted: AnsibleDesign.inkMuted,
          faint: AnsibleDesign.inkFaint,
          rule: AnsibleDesign.rule,
          accent: AnsibleDesign.ochre,
        );
      case ElixScreenStyle.ink:
        return const ElixScreenStyleData(
          background: AnsibleDesign.darkPaper,
          surface: AnsibleDesign.darkPaperElev,
          foreground: AnsibleDesign.darkInk,
          muted: AnsibleDesign.darkInkMuted,
          faint: AnsibleDesign.darkInkFaint,
          rule: AnsibleDesign.darkRule,
          accent: AnsibleDesign.darkOchre,
        );
      case ElixScreenStyle.system:
        return brightness == Brightness.dark
            ? ElixScreenStyle.ink.dataFor(brightness)
            : ElixScreenStyle.paper.dataFor(brightness);
    }
  }

  static ElixScreenStyle fromStorage(String? value) {
    return ElixScreenStyle.values.firstWhere(
      (style) => style.storageValue == value,
      orElse: () => ElixScreenStyle.paper,
    );
  }
}

extension ElixBoardMotionUi on ElixBoardMotion {
  String get storageValue => name;

  String get label {
    switch (this) {
      case ElixBoardMotion.slide:
        return 'Slide';
      case ElixBoardMotion.book:
        return 'Book';
      case ElixBoardMotion.cube:
        return 'Cube';
    }
  }

  String get zhLabel {
    switch (this) {
      case ElixBoardMotion.slide:
        return '平移';
      case ElixBoardMotion.book:
        return '翻書';
      case ElixBoardMotion.cube:
        return '翻立方';
    }
  }

  String get title {
    switch (this) {
      case ElixBoardMotion.slide:
        return 'Slide';
      case ElixBoardMotion.book:
        return 'Book';
      case ElixBoardMotion.cube:
        return 'Cube';
    }
  }

  String get description {
    switch (this) {
      case ElixBoardMotion.slide:
        return 'Two pages slide side to side with no 3D effect.';
      case ElixBoardMotion.book:
        return 'Boards turn like left and right pages with light perspective.';
      case ElixBoardMotion.cube:
        return 'Fuller rotateY motion with a stronger switch feel.';
    }
  }

  static ElixBoardMotion fromStorage(String? value) {
    if (value == 'light') return ElixBoardMotion.slide;
    return ElixBoardMotion.values.firstWhere(
      (motion) => motion.storageValue == value,
      orElse: () => ElixBoardMotion.book,
    );
  }
}

class ElixScreenStyleData {
  const ElixScreenStyleData({
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.faint,
    required this.rule,
    required this.accent,
  });

  final Color background;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color faint;
  final Color rule;
  final Color accent;
}

class ElixScreenStyleScope extends InheritedWidget {
  const ElixScreenStyleScope({
    super.key,
    required this.style,
    required super.child,
  });

  final ElixScreenStyle style;

  static ElixScreenStyle styleOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<ElixScreenStyleScope>()
            ?.style ??
        ElixScreenStyle.paper;
  }

  static ElixScreenStyleData dataOf(BuildContext context) {
    return styleOf(context).dataFor(Theme.of(context).brightness);
  }

  @override
  bool updateShouldNotify(ElixScreenStyleScope oldWidget) {
    return oldWidget.style != style;
  }
}
