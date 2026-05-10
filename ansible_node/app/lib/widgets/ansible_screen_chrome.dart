import 'package:flutter/material.dart';

import '../theme/ansible_design.dart';

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
    final leading = leadingLabel ?? '← 草地';
    return Scaffold(
      backgroundColor: AnsibleDesign.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(22, paddingTop, 22, 14),
              child: Row(
                children: [
                  _NavTextButton(label: leading, onTap: onLeading),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        color: AnsibleDesign.inkFaint,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 68,
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
  });

  final String glyph;
  final String label;
  final String en;
  final String? sub;
  final String? value;
  final VoidCallback? onTap;
  final bool last;
  final bool danger;

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
            const SizedBox(width: 12),
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
                          fontSize: 14.5,
                          color: color,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      Text(
                        en,
                        style: const TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 8.5,
                          letterSpacing: 1.4,
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
                        fontSize: 11.5,
                        color: AnsibleDesign.inkFaint,
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
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 9.5,
                  letterSpacing: 1.2,
                  color: AnsibleDesign.inkMuted,
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Text(
              '›',
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 13,
                color: AnsibleDesign.inkFaint,
              ),
            ),
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
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 12,
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
    return SizedBox(
      width: 68,
      child: Align(
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
                fontFamily: AnsibleDesign.mono,
                fontSize: AnsibleDesign.navTextSize,
                letterSpacing: 1.5,
                color: AnsibleDesign.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
