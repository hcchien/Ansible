import 'package:flutter/material.dart';

import 'ansible_design.dart';

enum ElixScreenStyle { paper, ink, system }

extension ElixScreenStyleUi on ElixScreenStyle {
  String get storageValue => name;

  String get label {
    switch (this) {
      case ElixScreenStyle.paper:
        return 'Paper';
      case ElixScreenStyle.ink:
        return 'Ink';
      case ElixScreenStyle.system:
        return 'System';
    }
  }

  String get zhLabel {
    switch (this) {
      case ElixScreenStyle.paper:
        return 'Paper';
      case ElixScreenStyle.ink:
        return 'Ink';
      case ElixScreenStyle.system:
        return '跟隨系統';
    }
  }

  String get description {
    switch (this) {
      case ElixScreenStyle.paper:
        return '白天的廣場';
      case ElixScreenStyle.ink:
        return '晚上一個人寫字';
      case ElixScreenStyle.system:
        return '跟著系統外觀';
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
