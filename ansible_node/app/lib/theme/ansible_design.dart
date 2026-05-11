import 'package:flutter/material.dart';

class AnsibleDesign {
  static const brandName = 'Elix';
  static const paper = Color(0xFFFAF6EC);
  static const paperElev = Color(0xFFF0EBDA);
  static const paperDeep = Color(0xFFE8E1CF);
  static const ink = Color(0xFF1A1815);
  static const inkMuted = Color(0xFF3A3530);
  static const inkFaint = Color(0xFF8A847A);
  static const rule = Color(0xFFD9D2BE);
  static const ruleSoft = Color(0xFFE4DDC8);
  static const accent = Color(0xFFB97A3C);
  static const accentSoft = Color(0xFFF0EBDA);
  static const spore = Color(0xFF4A6B5E);
  static const danger = Color(0xFF7A3E1E);

  static const serif = 'Noto Serif TC';
  static const serifEn = 'Newsreader';
  static const sans = 'Noto Sans TC';
  static const mono = 'JetBrains Mono';
  static const appTextScale = 1.08;
  static const navTextSize = 12.5;
  static const readingTextSize = 17.0;
  static const previewTextSize = 16.5;
  static const fallback = [
    'Noto Serif TC',
    'Noto Sans TC',
    'PingFang TC',
    'Songti TC',
    'PMingLiU',
    'MingLiU',
  ];

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
      fontFamily: serif,
      fontFamilyFallback: fallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
        fontFamily: serif,
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
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
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
          backgroundColor: ink,
          foregroundColor: paper,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: serif,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.6,
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
        color: paperElev,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: ruleSoft, width: 0.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paperElev,
        selectedColor: paperDeep,
        side: const BorderSide(color: rule, width: 0.5),
        labelStyle: const TextStyle(color: inkMuted, fontFamily: mono),
      ),
    );
  }
}

class AnsibleMark extends StatelessWidget {
  const AnsibleMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AnsibleDesign.ink;
    return CustomPaint(
      size: Size.square(size),
      painter: _ElixMarkPainter(c, AnsibleDesign.accent),
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
        fontFamily: AnsibleDesign.serifEn,
        fontFamilyFallback: AnsibleDesign.fallback,
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1,
        letterSpacing: 0,
        color: color ?? AnsibleDesign.ink,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
      child: Row(
        children: [
          const AnsibleMark(size: 22),
          const SizedBox(width: 9),
          const ElixWordmark(fontSize: 23),
          const Spacer(),
          actions ??
              AnsibleStatusChip(label: chip, dot: dot ?? AnsibleDesign.spore),
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
                fontSize: 9.5,
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
