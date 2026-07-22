import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import '../theme/ansible_design.dart';
import '../theme/elix_screen_style.dart';

class AnsibleScreenScaffold extends StatelessWidget {
  const AnsibleScreenScaffold({
    super.key,
    required this.title,
    required this.child,
    this.leadingLabel,
    this.onLeading,
    this.trailing,
    this.paddingTop = 8,
  });

  final String title;
  final String? leadingLabel;
  final VoidCallback? onLeading;
  final Widget? trailing;
  final Widget child;
  final double paddingTop;

  @override
  Widget build(BuildContext context) {
    final leading = leadingLabel ?? context.uiCopy(zh: '← 草地', en: '← Home');
    final screenStyle = ElixScreenStyleScope.dataOf(context);
    return Scaffold(
      backgroundColor: screenStyle.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(22, paddingTop, 22, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _NavTextButton(label: leading, onTap: onLeading),
                  ),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 11,
                      letterSpacing: 2.4,
                    ).copyWith(color: screenStyle.muted),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing ?? const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class AnsibleMonoLabel extends StatelessWidget {
  const AnsibleMonoLabel(this.label, {super.key, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 10,
          letterSpacing: 1.5,
          color: AnsibleDesign.inkFaint,
        ),
      ),
    );
  }
}

class AnsibleRuleGroup extends StatelessWidget {
  const AnsibleRuleGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AnsibleDesign.rule, width: 0.5),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class AnsibleSettingsRow extends StatelessWidget {
  const AnsibleSettingsRow({
    super.key,
    required this.glyph,
    required this.label,
    required this.en,
    this.sub,
    this.value,
    this.onTap,
    this.last = false,
    this.danger = false,
    this.valueColor,
    this.trailingIcon = Icons.chevron_right,
  });

  final String glyph;
  final String label;
  final String en;
  final String? sub;
  final String? value;
  final VoidCallback? onTap;
  final bool last;
  final bool danger;
  final Color? valueColor;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AnsibleDesign.danger : AnsibleDesign.ink;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: last
                ? BorderSide.none
                : const BorderSide(color: AnsibleDesign.ruleSoft, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            AnsibleGlyphBox(glyph: glyph, danger: danger),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: AnsibleDesign.serif,
                          fontSize: 16,
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        en,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 10,
                          letterSpacing: 1.3,
                          color: AnsibleDesign.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        color: AnsibleDesign.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 10),
              Text(
                value!,
                style: const TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  fontSize: 14,
                ).copyWith(color: valueColor ?? AnsibleDesign.inkMuted),
              ),
            ],
            const SizedBox(width: 5),
            Icon(trailingIcon, size: 16, color: AnsibleDesign.inkFaint),
          ],
        ),
      ),
    );
  }
}

class AnsibleGlyphBox extends StatelessWidget {
  const AnsibleGlyphBox({super.key, required this.glyph, this.danger = false});

  final String glyph;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 15,
          color: danger ? AnsibleDesign.danger : AnsibleDesign.inkMuted,
        ),
      ),
    );
  }
}

class AnsiblePillButton extends StatelessWidget {
  const AnsiblePillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 7),
              Text(label),
            ],
          );
    if (filled) {
      return FilledButton(onPressed: onPressed, child: child);
    }
    return OutlinedButton(onPressed: onPressed, child: child);
  }
}

class _NavTextButton extends StatelessWidget {
  const _NavTextButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 14,
              color: AnsibleDesign.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
