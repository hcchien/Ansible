import 'package:flutter/material.dart';

import 'ansible_design.dart';

enum ElixScreenStyle { paper, vellum, deep, canopy }

extension ElixScreenStyleUi on ElixScreenStyle {
  String get storageValue => name;

  String get label {
    switch (this) {
      case ElixScreenStyle.paper:
        return 'Paper';
      case ElixScreenStyle.vellum:
        return 'Vellum';
      case ElixScreenStyle.deep:
        return 'Deep';
      case ElixScreenStyle.canopy:
        return 'Canopy';
    }
  }

  String get zhLabel {
    switch (this) {
      case ElixScreenStyle.paper:
        return '紙面';
      case ElixScreenStyle.vellum:
        return '羊皮';
      case ElixScreenStyle.deep:
        return '深紙';
      case ElixScreenStyle.canopy:
        return '林下';
    }
  }

  String get description {
    switch (this) {
      case ElixScreenStyle.paper:
        return '標準閱讀背景';
      case ElixScreenStyle.vellum:
        return '較柔的工作面';
      case ElixScreenStyle.deep:
        return '較重的沉浸面';
      case ElixScreenStyle.canopy:
        return '偏綠的信任面';
    }
  }

  ElixScreenStyleData get data {
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
      case ElixScreenStyle.vellum:
        return const ElixScreenStyleData(
          background: AnsibleDesign.paperElev,
          surface: AnsibleDesign.paper,
          foreground: AnsibleDesign.ink,
          muted: AnsibleDesign.inkMuted,
          faint: AnsibleDesign.inkFaint,
          rule: AnsibleDesign.rule,
          accent: AnsibleDesign.ochre,
        );
      case ElixScreenStyle.deep:
        return const ElixScreenStyleData(
          background: AnsibleDesign.paperDeep,
          surface: AnsibleDesign.paperElev,
          foreground: AnsibleDesign.ink,
          muted: AnsibleDesign.inkMuted,
          faint: AnsibleDesign.inkFaint,
          rule: AnsibleDesign.rule,
          accent: AnsibleDesign.ember,
        );
      case ElixScreenStyle.canopy:
        return const ElixScreenStyleData(
          background: Color(0xFFEAF0D8),
          surface: Color(0xFFF4F7E8),
          foreground: AnsibleDesign.ink,
          muted: AnsibleDesign.inkMuted,
          faint: AnsibleDesign.inkFaint,
          rule: AnsibleDesign.rule,
          accent: AnsibleDesign.moss,
        );
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
    return styleOf(context).data;
  }

  @override
  bool updateShouldNotify(ElixScreenStyleScope oldWidget) {
    return oldWidget.style != style;
  }
}
