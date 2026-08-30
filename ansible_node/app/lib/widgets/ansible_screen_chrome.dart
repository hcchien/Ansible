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
    this.eyebrow,
    this.showBrand = true,
  });

  final String title;
  final String? leadingLabel;
  final VoidCallback? onLeading;
  final Widget? trailing;
  final Widget child;
  final double paddingTop;
  final String? eyebrow;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    final leading = leadingLabel ?? context.uiCopy(zh: '← 草地', en: '← Home');
    final style = ElixScreenStyleScope.styleOf(context);
    final isInk =
        style == ElixScreenStyle.ink ||
        (style == ElixScreenStyle.system &&
            Theme.of(context).brightness == Brightness.dark);
    final screenStyle = style.dataFor(Theme.of(context).brightness);

    // A Paper screen may be reached while the app follows the system's dark
    // theme. Its scaffold already uses Paper colours, but Material controls
    // (disabled buttons, icon buttons, inputs) used to inherit Ink colours,
    // leaving their labels nearly invisible on the light background.
    return Theme(
      data: isInk ? AnsibleDesign.darkTheme() : AnsibleDesign.theme(),
      child: Scaffold(
        backgroundColor: screenStyle.background,
        body: SafeArea(
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: screenStyle.rule,
                      width: AnsibleDesign.hairline,
                    ),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(16, paddingTop, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _NavTextButton(label: leading, onTap: onLeading),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.2,
                        color: screenStyle.muted,
                      ),
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
    final faint = Theme.of(context).brightness == Brightness.dark
        ? AnsibleDesign.darkInkFaint
        : AnsibleDesign.inkFaint;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 10,
          letterSpacing: 1.5,
          color: faint,
        ),
      ),
    );
  }
}

class AnsibleRuleGroup extends StatelessWidget {
  const AnsibleRuleGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 18),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final rule = Theme.of(context).brightness == Brightness.dark
        ? AnsibleDesign.darkRule
        : AnsibleDesign.rule;
    final surface = Theme.of(context).brightness == Brightness.dark
        ? AnsibleDesign.darkPaperWhite
        : AnsibleDesign.paperWhite;
    return Padding(
      padding: margin,
      child: Material(
        color: surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AnsibleDesign.cardRadius),
          side: BorderSide(color: rule, width: AnsibleDesign.hairline),
        ),
        child: Column(children: children),
      ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final faint = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    final ruleSoft = dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
    final dangerColor = dark ? AnsibleDesign.darkEmber : AnsibleDesign.danger;
    final color = danger ? dangerColor : ink;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: last
                ? BorderSide.none
                : BorderSide(color: ruleSoft, width: 0.5),
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
                        style: TextStyle(
                          fontFamily: AnsibleDesign.mono,
                          fontSize: 10,
                          letterSpacing: 1.3,
                          color: faint,
                        ),
                      ),
                    ],
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub!,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.serif,
                        fontSize: 13,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFamily: AnsibleDesign.sans,
                    fontSize: 14,
                  ).copyWith(color: valueColor ?? muted),
                ),
              ),
            ],
            const SizedBox(width: 5),
            Icon(trailingIcon, size: 16, color: faint),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final dangerColor = dark ? AnsibleDesign.darkEmber : AnsibleDesign.danger;
    final fill = dark
        ? AnsibleDesign.darkTintLavender
        : AnsibleDesign.tintLavender;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: danger ? dangerColor.withValues(alpha: 0.08) : fill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: rule, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        glyph,
        style: TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 15,
          color: danger ? dangerColor : muted,
        ),
      ),
    );
  }
}

/// Editorial card used by settings, identity, Wallet, sync and disclosure
/// screens. It deliberately carries no elevation; the hairline and paper
/// contrast are the Forest Letter hierarchy.
class AnsibleSectionCard extends StatelessWidget {
  const AnsibleSectionCard({
    super.key,
    required this.child,
    this.label,
    this.accent = AnsibleDesign.accent,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
    this.surface,
  });

  final Widget child;
  final String? label;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final fill =
        surface ??
        (dark ? AnsibleDesign.darkPaperWhite : AnsibleDesign.paperWhite);
    final faint = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AnsibleDesign.cardRadius),
        border: Border.all(color: rule, width: AnsibleDesign.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 9),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: rule,
                    width: AnsibleDesign.hairline,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label!,
                      style: TextStyle(
                        fontFamily: AnsibleDesign.mono,
                        fontSize: 9,
                        letterSpacing: 1.45,
                        color: faint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class AnsibleSourceLabel extends StatelessWidget {
  const AnsibleSourceLabel(this.label, {super.key, this.color, this.dotColor});

  final String label;
  final Color? color;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final faint =
        color ?? (dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dotColor != null) ...[
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              letterSpacing: 1.45,
              color: faint,
            ),
          ),
        ),
      ],
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
    final muted = Theme.of(context).brightness == Brightness.dark
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
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
            style: TextStyle(
              fontFamily: AnsibleDesign.sans,
              fontSize: 14,
              color: muted,
            ),
          ),
        ),
      ),
    );
  }
}
