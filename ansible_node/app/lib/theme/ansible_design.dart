import 'package:flutter/material.dart';

class AnsibleDesign {
  static const paper = Color(0xFFF0EEE6);
  static const paperElev = Color(0xFFF8F5EC);
  static const paperDeep = Color(0xFFE7E2D6);
  static const ink = Color(0xFF2F2A20);
  static const inkMuted = Color(0xFF6B6253);
  static const inkFaint = Color(0xFF988F80);
  static const rule = Color(0xFFD4CCBD);
  static const ruleSoft = Color(0xFFE2DCD0);
  static const accent = Color(0xFFC76C35);
  static const accentSoft = Color(0xFFEAD1B9);
  static const spore = Color(0xFF6F8B55);
  static const danger = Color(0xFFA34432);

  static const serif = 'Noto Serif TC';
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
      painter: _AnsibleMarkPainter(c),
    );
  }
}

class _AnsibleMarkPainter extends CustomPainter {
  const _AnsibleMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 32;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    stroke.strokeWidth = 1.5 * scale;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(11 * scale, 16 * scale),
        radius: 5 * scale,
      ),
      -1.5708,
      3.1416,
      false,
      stroke,
    );
    stroke
      ..strokeWidth = 1 * scale
      ..color = color.withValues(alpha: 0.55);
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(11 * scale, 16 * scale),
        radius: 8 * scale,
      ),
      -1.5708,
      3.1416,
      false,
      stroke,
    );
    canvas.drawCircle(Offset(11 * scale, 16 * scale), 2.5 * scale, fill);
    stroke
      ..strokeWidth = 1.25 * scale
      ..color = color;
    canvas.drawCircle(Offset(24 * scale, 16 * scale), 2.5 * scale, stroke);
  }

  @override
  bool shouldRepaint(covariant _AnsibleMarkPainter oldDelegate) {
    return oldDelegate.color != color;
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
          const Text(
            'ansible',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w300,
              letterSpacing: 0,
            ),
          ),
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
          Text(
            zh,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AnsibleDesign.ink,
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
