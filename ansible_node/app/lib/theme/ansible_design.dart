import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Elix Design System — "Forest Letter".
// The forum surfaces use warm paper, forest ink, ochre trust signals and
// restrained hairlines.  Content is editorial serif; product chrome is sans;
// handles, policies and timestamps are mono.
// ─────────────────────────────────────────────────────────────────────────────

class AnsibleDesign {
  static const brandName = 'Elix';

  // ── Light (Paper — canonical) ─────────────────────────────────────────────
  static const paper = Color(0xFFFBF7DC);
  static const paperElev = Color(0xFFF4EEC6);
  static const paperDeep = Color(0xFFE8DEAA);
  static const paperWhite = Color(0xFFFBF7DC);
  static const ink = Color(0xFF1F2E20);
  static const inkMuted = Color(0xFF3D4E3D);
  static const inkFaint = Color(0xFF88826E);
  static const rule = Color(0xFFD6CB94);
  static const ruleSoft = Color(0xFFE3DAB0);
  static const accent = Color(0xFFB88C2E);
  static const accentSoft = Color(0xFFF4E8BE);
  static const signalSoft = Color(0xFF93A971);
  static const tintSky = Color(0xFFF1EFD8);
  static const tintLavender = Color(0xFFF4EEC6);
  static const tintCitron = Color(0xFFE8DEAA);
  static const spore = Color(0xFF5A6E3A);
  static const moss = Color(0xFF5A6E3A);
  static const lavender = Color(0xFF5A6E3A);
  static const highlight = Color(0xFFB88C2E);
  // Destructive/warning text must stay readable on bone paper, so it keeps a
  // warm rust; the design's citron "ember" slot is decorative only.
  static const danger = Color(0xFF9A4A24);
  static const ember = danger;
  static const ochre = accent;

  // ── Dark (Ink — warm black counterpart) ───────────────────────────────────
  static const darkPaper = Color(0xFF0E1A0F);
  static const darkPaperElev = Color(0xFF16221A);
  static const darkPaperDeep = Color(0xFF1F2D24);
  static const darkPaperWhite = Color(0xFF0E1A0F);
  static const darkInk = Color(0xFFE8E0BE);
  static const darkInkMuted = Color(0xFFB8B49A);
  static const darkInkFaint = Color(0xFF7C8071);
  static const darkRule = Color(0xFF2A3526);
  static const darkRuleSoft = Color(0xFF1F291E);
  static const darkSignalSoft = Color(0xFF93A971);
  static const darkTintSky = Color(0xFF16221A);
  static const darkTintLavender = Color(0xFF1F2D24);
  static const darkTintCitron = Color(0xFF1F2D24);
  static const darkOchre = Color(0xFFD9AB4E);
  static const darkMoss = Color(0xFF93A971);
  static const darkLavender = Color(0xFF93A971);
  static const darkHighlight = Color(0xFFD9AB4E);
  static const darkEmber = Color(0xFFC97B52); // warning text (dark)

  // ── Typography ────────────────────────────────────────────────────────────
  static const display = 'Noto Serif TC';
  static const serif = 'Noto Serif TC';
  static const serifEn = 'Newsreader';
  static const sans = 'Noto Sans TC';
  static const mono = 'JetBrains Mono';
  static const appTextScale = 1.06;
  static const navTextSize = 11.5;
  static const readingTextSize = 16.0;
  static const previewTextSize = 15.5;
  static const fallback = [
    'Noto Serif TC',
    'Newsreader',
    'Noto Sans TC',
    'PingFang TC',
    'Songti TC',
    'PMingLiU',
    'MingLiU',
  ];

  /// Paper screens always use this switch palette, even when the device is in
  /// dark mode. Some Paper surfaces intentionally stay light, and inheriting
  /// the app-wide dark switch theme made their selected state look black.
  static SwitchThemeData paperSwitchTheme() => SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      return paperWhite;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      if (states.contains(WidgetState.disabled)) {
        return selected ? moss.withValues(alpha: 0.52) : paperDeep;
      }
      return selected ? moss : rule;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected) ? moss : rule;
    }),
  );

  // ── Light theme ───────────────────────────────────────────────────────────
  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      primary: ink,
      onPrimary: paper,
      secondary: accent,
      onSecondary: paper,
      surface: paper,
      onSurface: ink,
      surfaceContainerHighest: paperElev,
      outline: rule,
      error: danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: sans,
      fontFamilyFallback: fallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
        fontFamily: sans,
        fontFamilyFallback: fallback,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: ruleSoft, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paperElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ink),
        ),
        labelStyle: const TextStyle(color: inkMuted),
        hintStyle: const TextStyle(
          color: inkFaint,
          fontStyle: FontStyle.italic,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: sans,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: rule, width: 0.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: inkMuted),
      ),
      iconTheme: const IconThemeData(color: inkMuted),
      cardTheme: CardThemeData(
        color: paperWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: ruleSoft, width: 0.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paperElev,
        selectedColor: paperDeep,
        side: const BorderSide(color: rule, width: 0.5),
        labelStyle: const TextStyle(color: inkMuted, fontFamily: mono),
      ),
      // The Material 3 default uses a very dark unselected track with this
      // colour scheme.  On paper it made ON and OFF settings look almost the
      // same, which is particularly unsafe for consent-bearing controls such
      // as Fediverse publication.  Keep the thumb/track contrast explicit.
      switchTheme: paperSwitchTheme(),
    );
  }

  // ── Dark theme (Pine) ─────────────────────────────────────────────────────
  static ThemeData darkTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: darkOchre,
      brightness: Brightness.dark,
      primary: darkInk,
      onPrimary: darkPaper,
      secondary: darkOchre,
      onSecondary: darkPaper,
      surface: darkPaper,
      onSurface: darkInk,
      surfaceContainerHighest: darkPaperElev,
      outline: darkRule,
      error: darkEmber,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkPaper,
      fontFamily: sans,
      fontFamilyFallback: fallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: darkInk,
        displayColor: darkInk,
        fontFamily: sans,
        fontFamilyFallback: fallback,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPaper,
        foregroundColor: darkInk,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(color: darkRuleSoft, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkPaperElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkRule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkRule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkInk),
        ),
        labelStyle: const TextStyle(color: darkInkMuted),
        hintStyle: const TextStyle(
          color: darkInkFaint,
          fontStyle: FontStyle.italic,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkOchre,
          foregroundColor: darkPaper,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: sans,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkInk,
          side: const BorderSide(color: darkRule, width: 0.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: darkInkMuted),
      ),
      iconTheme: const IconThemeData(color: darkInkMuted),
      cardTheme: CardThemeData(
        color: darkPaperWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: darkRuleSoft, width: 0.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: darkPaperElev,
        selectedColor: darkPaperDeep,
        side: const BorderSide(color: darkRule, width: 0.5),
        labelStyle: const TextStyle(color: darkInkMuted, fontFamily: mono),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return darkPaperDeep;
          return darkPaper;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return darkPaperDeep;
          return states.contains(WidgetState.selected) ? darkMoss : darkRule;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkMoss;
          return darkRule;
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ElixThemeController — persists ThemeMode to SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

class ElixThemeController extends ChangeNotifier {
  static const _key = 'elix-theme';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'light') {
      _mode = ThemeMode.light;
    } else if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, isDark ? 'dark' : 'light');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Existing components — kept intact
// ─────────────────────────────────────────────────────────────────────────────

class AnsibleMark extends StatelessWidget {
  const AnsibleMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Default to the theme's ink so the mark stays visible on the Ink ground;
    // the trust dot keeps the accent, which reads on both.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? (dark ? AnsibleDesign.darkInk : AnsibleDesign.ink);
    return CustomPaint(
      size: Size.square(size),
      painter: _ElixMarkPainter(
        c,
        dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent,
      ),
    );
  }
}

class ElixWordmark extends StatelessWidget {
  const ElixWordmark({super.key, this.fontSize = 24, this.color});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      AnsibleDesign.brandName,
      style: TextStyle(
        fontFamily: AnsibleDesign.display,
        fontFamilyFallback: AnsibleDesign.fallback,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -0.6,
        color:
            color ??
            (Theme.of(context).brightness == Brightness.dark
                ? AnsibleDesign.darkInk
                : AnsibleDesign.ink),
      ),
    );
  }
}

class _ElixMarkPainter extends CustomPainter {
  const _ElixMarkPainter(this.color, this.accent);

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 200;
    final center = Offset(size.width / 2, size.height / 2);
    Offset p(double x, double y) => center + Offset(x * s, y * s);
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.74)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.2 * s;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(0.5235987756);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawLine(p(-60, 40), p(60, 40), stroke);
    canvas.drawLine(p(-60, 40), p(0, -60), stroke);
    canvas.drawLine(p(60, 40), p(0, -60), stroke);
    canvas.drawCircle(p(-60, 40), 14 * s, fill);
    canvas.drawCircle(p(60, 40), 14 * s, fill);
    canvas.drawCircle(p(0, -60), 14 * s, fill);
    canvas.drawCircle(
      p(0, 6),
      8 * s,
      Paint()
        ..color = accent
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ElixMarkPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.accent != accent;
  }
}

class AnsibleHeader extends StatelessWidget {
  const AnsibleHeader({super.key, this.chip = '本地', this.dot, this.actions});

  final String chip;
  final Color? dot;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final chipLabel = chip == '本地'
        ? context.uiCopy(zh: '本地', en: 'Local')
        : chip;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
      child: Row(
        children: [
          const AnsibleMark(size: 22),
          const SizedBox(width: 9),
          const ElixWordmark(fontSize: 23),
          const Spacer(),
          actions ??
              AnsibleStatusChip(
                label: chipLabel,
                dot: dot ?? AnsibleDesign.spore,
              ),
        ],
      ),
    );
  }
}

class AnsibleStatusChip extends StatelessWidget {
  const AnsibleStatusChip({super.key, required this.label, this.dot});

  final String label;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: AnsibleDesign.rule, width: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot ?? AnsibleDesign.spore,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11.5,
              color: AnsibleDesign.inkMuted,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class AnsibleSectionHead extends StatelessWidget {
  const AnsibleSectionHead({
    super.key,
    required this.zh,
    required this.en,
    this.action,
  });

  final String zh;
  final String en;
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Text(
              zh,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AnsibleDesign.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              en,
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                color: AnsibleDesign.inkFaint,
                letterSpacing: 1.4,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null)
            Text(
              action!,
              style: const TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 10,
                color: AnsibleDesign.inkMuted,
                letterSpacing: 0.8,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Elix UI components
// ─────────────────────────────────────────────────────────────────────────────

/// Trust badge pill. [kind] is one of: 'PK', 'DID', 'WEB', 'BASIC'.
/// Restyle: hand-stamped look — white paper chip, dashed colored border,
/// slight counter-clockwise rotation (matches the web `.pk-badge`).
class ElixSignedPill extends StatelessWidget {
  const ElixSignedPill({super.key, required this.kind});

  final String kind; // 'PK' | 'DID' | 'WEB' | 'BASIC'

  Color _fg(bool dark) {
    switch (kind) {
      case 'PK':
        return dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
      case 'DID':
        return dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss;
      case 'WEB':
        return dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
      default: // BASIC
        return dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = _fg(dark);
    final bg = dark ? AnsibleDesign.darkPaperWhite : AnsibleDesign.paperWhite;
    return Transform.rotate(
      angle: -0.035, // ≈ -2°
      child: CustomPaint(
        painter: _DashedRectPainter(color: fg, fill: bg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '✓',
                style: TextStyle(fontSize: 10, color: fg, height: 1.35),
              ),
              const SizedBox(width: 4),
              Text(
                kind,
                style: TextStyle(
                  fontFamily: AnsibleDesign.sans,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: fg,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded rect with a dashed hairline border — the "hand-stamped" chip
/// treatment used by trust badges in the yellow-paper restyle.
class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color, required this.fill});

  final Color color;
  final Color fill;

  static const double radius = 5;
  static const double strokeWidth = 1.5;
  static const double dash = 4;
  static const double gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);

    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()..addRRect(rrect.deflate(strokeWidth / 2));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), border);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.fill != fill;
  }
}

/// "Why this post" mono-caps label row.
/// [kind] is one of: 'follow', 'board', 'circle', 'murmur', 'note'.
class ElixSourceLabel extends StatelessWidget {
  const ElixSourceLabel({super.key, required this.kind, this.label});

  final String kind; // 'follow' | 'board' | 'circle' | 'murmur' | 'note'
  final String? label;

  static const _icons = {
    'follow': '↳',
    'board': '▦',
    'circle': '◎',
    'murmur': '∿',
    'note': '✎',
  };

  Color _color(bool dark) {
    switch (kind) {
      case 'board':
        return dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss;
      case 'circle':
        return dark ? AnsibleDesign.ember : AnsibleDesign.ember;
      default:
        return dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = _color(dark);
    final icon = _icons[kind] ?? '·';
    final text = label ?? kind.toUpperCase();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: TextStyle(fontSize: 10, color: color, height: 1)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontFamily: AnsibleDesign.mono,
            fontSize: 11,
            letterSpacing: 1.2,
            color: color,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Colored audience chip.
/// [kind]: 'followers' (ochre), 'board' (moss), 'circle' (ember/warning).
class AudienceChip extends StatelessWidget {
  const AudienceChip({super.key, required this.label, required this.kind});

  final String label;
  final String kind; // 'followers' | 'board' | 'circle'

  Color _bg(bool dark) {
    switch (kind) {
      case 'followers':
        return (dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre)
            .withValues(alpha: 0.15);
      case 'board':
        return (dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss).withValues(
          alpha: 0.15,
        );
      case 'circle':
        return AnsibleDesign.ember.withValues(alpha: 0.15);
      default:
        return dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
    }
  }

  Color _fg(bool dark) {
    switch (kind) {
      case 'followers':
        return dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
      case 'board':
        return dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss;
      case 'circle':
        return AnsibleDesign.ember;
      default:
        return dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(dark),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AnsibleDesign.mono,
          fontSize: 10,
          letterSpacing: 0.8,
          color: _fg(dark),
          height: 1.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Focus Mode — Room navigation + personal board components
// ─────────────────────────────────────────────────────────────────────────────

/// Data class for a room entry in the [ElixRoomHeader] dropdown.
class ElixRoomItem {
  const ElixRoomItem({
    required this.id,
    required this.label,
    this.badge,
    this.active = false,
    this.murmurCount,
    this.noteCount,
  });

  final String id;
  final String label;
  final int? badge;
  final bool active;

  /// Number of murmurs — shown as a sub-row under the active personal room.
  final int? murmurCount;

  /// Number of notes — shown as a sub-row under the active personal room.
  final int? noteCount;
}

/// Room header: shows Elix mark + current room name + ochre chevron.
/// Tap reveals an inline dropdown (A·02 spec) — no modal dimming, no backdrop.
class ElixRoomHeader extends StatefulWidget {
  const ElixRoomHeader({
    super.key,
    required this.roomLabel,
    required this.rooms,
    required this.onRoomSelected,
  });

  final String roomLabel;
  final List<ElixRoomItem> rooms;
  final ValueChanged<String> onRoomSelected;

  @override
  State<ElixRoomHeader> createState() => _ElixRoomHeaderState();
}

class _ElixRoomHeaderState extends State<ElixRoomHeader> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final mutedColor = dark
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
    final faintColor = dark
        ? AnsibleDesign.darkInkFaint
        : AnsibleDesign.inkFaint;
    final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
    // A·02: popup bg = base paper (bg), not elevated — matches design's white-ish card
    final popupBg = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
    final popupBorder = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    // A·02: active row bg = bg-soft = paperElev (lighter tint)
    final bgSoftColor = dark
        ? AnsibleDesign.darkPaperElev
        : AnsibleDesign.paperElev;
    final ruleColor = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    // Hairline separators between dropdown rows use rule-soft (lighter)
    final ruleSoftColor = dark
        ? AnsibleDesign.darkRuleSoft
        : AnsibleDesign.ruleSoft;

    return PopupMenuButton<String>(
      onOpened: () => setState(() => _isOpen = true),
      onCanceled: () => setState(() => _isOpen = false),
      onSelected: (id) {
        setState(() => _isOpen = false);
        widget.onRoomSelected(id);
      },
      color: popupBg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: popupBorder, width: 0.5),
      ),
      offset: const Offset(0, 36),
      itemBuilder: (_) => [
        for (int i = 0; i < widget.rooms.length; i++)
          PopupMenuItem<String>(
            value: widget.rooms[i].id,
            padding: EdgeInsets.zero,
            child: _RoomMenuItemWidget(
              room: widget.rooms[i],
              isFirst: i == 0,
              inkColor: inkColor,
              mutedColor: mutedColor,
              faintColor: faintColor,
              ochreColor: ochreColor,
              bgSoftColor: bgSoftColor,
              ruleColor: ruleColor,
              ruleSoftColor: ruleSoftColor,
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnsibleMark(size: 14, color: inkColor),
          const SizedBox(width: 7),
          Text(
            widget.roomLabel,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 17,
              fontWeight: FontWeight.w500,
              color: inkColor,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 5),
          AnimatedRotation(
            turns: _isOpen ? 0.5 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: ochreColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Single item in the room dropdown (A·02 spec).
/// Uses a top-border separator instead of PopupMenuDivider to avoid
/// Flutter's popup-height miscalculation with tiny-height dividers.
class _RoomMenuItemWidget extends StatelessWidget {
  const _RoomMenuItemWidget({
    required this.room,
    required this.isFirst,
    required this.inkColor,
    required this.mutedColor,
    required this.faintColor,
    required this.ochreColor,
    required this.bgSoftColor,
    required this.ruleColor,
    required this.ruleSoftColor,
  });

  final ElixRoomItem room;
  final bool isFirst;
  final Color inkColor;
  final Color mutedColor;
  final Color faintColor;
  final Color ochreColor;
  final Color bgSoftColor;
  final Color ruleColor;
  final Color ruleSoftColor;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      decoration: room.active
          ? BoxDecoration(
              color: bgSoftColor,
              borderRadius: BorderRadius.circular(7),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main row: dot · name · badge / active state
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  width: room.active ? 7 : 6,
                  height: room.active ? 7 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: room.active ? ochreColor : Colors.transparent,
                    border: Border.all(
                      color: room.active ? ochreColor : ruleColor,
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    room.label,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.serif,
                      fontSize: 14,
                      fontWeight: room.active
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: room.id == 'settings' ? mutedColor : inkColor,
                    ),
                  ),
                ),
                if (room.active) ...[
                  const SizedBox(width: 8),
                  Text(
                    context.uiCopy(zh: '在這', en: 'Here'),
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 9,
                      color: ochreColor,
                      letterSpacing: 0.10,
                    ),
                  ),
                ] else if (room.badge != null && room.badge! > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    context.uiCopy(
                      zh: '${room.badge} 新',
                      en: '${room.badge} new',
                    ),
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 9,
                      color: faintColor,
                      letterSpacing: 0.06,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Sub-rows for active room (murmur count + note count)
          if (room.active && room.murmurCount != null)
            _SubCountRow(
              label: context.uiCopy(
                zh: 'murmur · 短話 · ${room.murmurCount}',
                en: 'murmur · short text · ${room.murmurCount}',
              ),
              faintColor: faintColor,
            ),
          if (room.active && room.noteCount != null)
            _SubCountRow(
              label: context.uiCopy(
                zh: 'note · 整理過的長文 · ${room.noteCount}',
                en: 'note · long-form · ${room.noteCount}',
              ),
              faintColor: faintColor,
              isLast: true,
            ),
        ],
      ),
    );

    if (isFirst) return content;
    // Non-first items: draw a hairline separator on top using rule-soft (A·02 design)
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ruleSoftColor, width: 0.5)),
      ),
      child: content,
    );
  }
}

class _SubCountRow extends StatelessWidget {
  const _SubCountRow({
    required this.label,
    required this.faintColor,
    this.isLast = false,
  });

  final String label;
  final Color faintColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 32, right: 10, bottom: isLast ? 8 : 4),
      child: Row(
        children: [
          Text(
            '↳',
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9,
              color: faintColor,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: AnsibleDesign.serif,
              fontSize: 12.5,
              color: faintColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Personal board diary entry card.
/// [kind] is `'murmur'` (ochre pip) or `'note'` (moss pip).
class DiaryEntryCard extends StatelessWidget {
  const DiaryEntryCard({
    super.key,
    required this.kind,
    required this.title,
    required this.preview,
    required this.timeAgo,
    this.onTap,
  });

  final String kind; // 'murmur' | 'note'
  final String title;
  final String preview;
  final String timeAgo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AnsibleDesign.darkPaperWhite : AnsibleDesign.paperWhite;
    final border = dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final mutedColor = dark
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;
    final faintColor = dark
        ? AnsibleDesign.darkInkFaint
        : AnsibleDesign.inkFaint;
    final pipColor = kind == 'murmur'
        ? AnsibleDesign.ember
        : (dark ? AnsibleDesign.darkInk : AnsibleDesign.ink);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type pip
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pipColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty) ...[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: inkColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: mutedColor,
                        height: 1.45,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10,
                      color: faintColor,
                      letterSpacing: 0.4,
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

/// Floating 56 px circular AI action button with the Elix mark.
class ElixAIDot extends StatelessWidget {
  const ElixAIDot({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
    final ring = dark ? AnsibleDesign.darkLavender : AnsibleDesign.lavender;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          border: Border.all(color: ring, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Center(child: AnsibleMark(size: 26, color: Colors.white)),
      ),
    );
  }
}

/// AI agent bottom sheet — ochre-accented top border, privacy note.
/// Wrap the [body] with your result list or action buttons.
class ElixAgentSheet extends StatelessWidget {
  const ElixAgentSheet({
    super.key,
    required this.title,
    required this.body,
    this.onAccept,
    this.onDismiss,
    this.acceptLabel = '套用建議',
    this.privacyNote = '僅處理本機內容，不離開裝置',
  });

  final String title;
  final Widget body;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;
  final String acceptLabel;
  final String privacyNote;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
    final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final mutedColor = dark
        ? AnsibleDesign.darkInkMuted
        : AnsibleDesign.inkMuted;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: ochreColor.withValues(alpha: 0.55),
            width: 1.5,
          ),
          left: BorderSide(
            color: ochreColor.withValues(alpha: 0.18),
            width: 0.5,
          ),
          right: BorderSide(
            color: ochreColor.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ochreColor.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AnsibleMark(size: 20, color: ochreColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: inkColor,
                  ),
                ),
              ),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(Icons.close, size: 20, color: mutedColor),
                ),
            ],
          ),
          const SizedBox(height: 16),
          body,
          const SizedBox(height: 14),
          // Privacy note
          Row(
            children: [
              Icon(Icons.lock_outline, size: 12, color: mutedColor),
              const SizedBox(width: 5),
              Text(
                privacyNote == '僅處理本機內容，不離開裝置'
                    ? context.uiCopy(
                        zh: '僅處理本機內容，不離開裝置',
                        en: 'Processes local content only; does not leave device',
                      )
                    : privacyNote,
                style: TextStyle(
                  fontFamily: AnsibleDesign.mono,
                  fontSize: 10,
                  color: mutedColor,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          if (onAccept != null) ...[
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAccept,
              style: FilledButton.styleFrom(
                backgroundColor: ochreColor,
                foregroundColor: dark
                    ? AnsibleDesign.darkPaper
                    : AnsibleDesign.paper,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                acceptLabel == '套用建議'
                    ? context.uiCopy(zh: '套用建議', en: 'Apply Suggestion')
                    : acceptLabel,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
