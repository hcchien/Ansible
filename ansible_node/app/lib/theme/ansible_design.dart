import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Elix Forest Letter Design System
// Light theme: Bone Goose  ·  Dark theme: Pine
// ─────────────────────────────────────────────────────────────────────────────

class AnsibleDesign {
  static const brandName = 'Elix';

  // ── Light (Bone Goose) ────────────────────────────────────────────────────
  static const paper = Color(0xFFFBF7DC);
  static const paperElev = Color(0xFFF4EEC6);
  static const paperDeep = Color(0xFFE8DEAA);
  static const ink = Color(0xFF1F2E20);
  static const inkMuted = Color(0xFF3D4E3D);
  static const inkFaint = Color(0xFF88826E);
  static const rule = Color(0xFFD6CB94);
  static const ruleSoft = Color(0xFFE3DAB0);
  static const accent = Color(0xFFB88C2E); // ochre (trust dot)
  static const accentSoft = Color(0xFFD6B66B); // lighter ochre
  static const spore = Color(0xFF5A6E3A); // Moss
  static const moss = Color(0xFF5A6E3A); // alias — Forest Letter "moss"
  static const danger = Color(0xFF7E4A1E); // ember
  static const ember = Color(0xFF7E4A1E); // alias — Forest Letter "ember"
  static const ochre = Color(0xFFB88C2E); // alias — Forest Letter "ochre"

  // ── Dark (Pine) ───────────────────────────────────────────────────────────
  static const darkPaper = Color(0xFF0E1A0F);
  static const darkPaperElev = Color(0xFF16221A);
  static const darkPaperDeep = Color(0xFF1F2D24);
  static const darkInk = Color(0xFFE8E0BE);
  static const darkInkMuted = Color(0xFFB8B49A);
  static const darkInkFaint = Color(0xFF7C8071);
  static const darkRule = Color(0xFF2A3526);
  static const darkRuleSoft = Color(0xFF1F291E);
  static const darkOchre = Color(0xFFD9AB4E);
  static const darkMoss = Color(0xFF93A971);

  // ── Typography ────────────────────────────────────────────────────────────
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
      error: ember,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkPaper,
      fontFamily: serif,
      fontFamilyFallback: fallback,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: darkInk,
        displayColor: darkInk,
        fontFamily: serif,
        fontFamilyFallback: fallback,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPaper,
        foregroundColor: darkInk,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme:
          const DividerThemeData(color: darkRuleSoft, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkPaperElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: darkRule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: darkRule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
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
          backgroundColor: darkInk,
          foregroundColor: darkPaper,
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
        color: darkPaperElev,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: darkRuleSoft, width: 0.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: darkPaperElev,
        selectedColor: darkPaperDeep,
        side: const BorderSide(color: darkRule, width: 0.5),
        labelStyle:
            const TextStyle(color: darkInkMuted, fontFamily: mono),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ElixThemeController — persists ThemeMode to SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

class ElixThemeController extends ChangeNotifier {
  static const _key = 'elix-theme';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.light;
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

// ─────────────────────────────────────────────────────────────────────────────
// New Elix UI components
// ─────────────────────────────────────────────────────────────────────────────

/// Trust badge pill. [kind] is one of: 'PK', 'DID', 'WEB', 'BASIC'.
class ElixSignedPill extends StatelessWidget {
  const ElixSignedPill({super.key, required this.kind});

  final String kind; // 'PK' | 'DID' | 'WEB' | 'BASIC'

  Color _bg(bool dark) {
    switch (kind) {
      case 'PK':
        return dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
      case 'DID':
        return dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss;
      case 'WEB':
        return dark
            ? AnsibleDesign.darkPaperElev
            : AnsibleDesign.paperElev;
      default: // BASIC
        return dark
            ? AnsibleDesign.darkPaperDeep
            : AnsibleDesign.paperDeep;
    }
  }

  Color _fg(bool dark) {
    switch (kind) {
      case 'PK':
      case 'DID':
        return dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;
      default:
        return dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _bg(dark),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '✓',
            style: TextStyle(
              fontSize: 9,
              color: _fg(dark),
              height: 1.2,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            kind,
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: _fg(dark),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
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
            fontSize: 9.5,
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
        return (dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss)
            .withValues(alpha: 0.15);
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
  });

  final String id;
  final String label;
  final int? badge;
  final bool active;
}

/// Room header: shows current room name + chevron; tap reveals inline
/// `PopupMenuButton` dropdown — no modal dimming, no backdrop.
class ElixRoomHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final mutedColor = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final ochreColor = dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre;
    final popupBg = dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
    final popupBorder = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;

    return PopupMenuButton<String>(
      onSelected: onRoomSelected,
      color: popupBg,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: popupBorder, width: 0.5),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (_) => rooms.map((room) {
        return PopupMenuItem<String>(
          value: room.id,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: room.active ? ochreColor : Colors.transparent,
                  border: Border.all(
                    color: room.active ? ochreColor : mutedColor.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                room.label,
                style: TextStyle(
                  fontFamily: AnsibleDesign.serif,
                  fontSize: 15,
                  fontWeight: room.active ? FontWeight.w600 : FontWeight.w400,
                  color: inkColor,
                ),
              ),
              if (room.badge != null && room.badge! > 0) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: ochreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${room.badge}',
                    style: TextStyle(
                      fontFamily: AnsibleDesign.mono,
                      fontSize: 10,
                      color: ochreColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              roomLabel,
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 26,
                fontWeight: FontWeight.w500,
                color: inkColor,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: mutedColor,
            ),
          ],
        ),
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
    final bg = dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
    final border = dark ? AnsibleDesign.darkRuleSoft : AnsibleDesign.ruleSoft;
    final inkColor = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final mutedColor = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final faintColor = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
    final pipColor = kind == 'murmur'
        ? (dark ? AnsibleDesign.darkOchre : AnsibleDesign.ochre)
        : (dark ? AnsibleDesign.darkMoss : AnsibleDesign.moss);

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
                decoration: BoxDecoration(shape: BoxShape.circle, color: pipColor),
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
    final bg = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final markColor = dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bg,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(child: AnsibleMark(size: 26, color: markColor)),
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
    final mutedColor = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: ochreColor.withValues(alpha: 0.55), width: 1.5),
          left: BorderSide(color: ochreColor.withValues(alpha: 0.18), width: 0.5),
          right: BorderSide(color: ochreColor.withValues(alpha: 0.18), width: 0.5),
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
                privacyNote,
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
                foregroundColor:
                    dark ? AnsibleDesign.darkPaper : AnsibleDesign.paper,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(acceptLabel),
            ),
          ],
        ],
      ),
    );
  }
}

/// Floating theme toggle pill: "PAPER · LIGHT" / "INK · DARK".
class ElixThemePill extends StatelessWidget {
  const ElixThemePill({super.key, required this.controller});

  final ElixThemeController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dark = controller.isDark;
        final bg = dark ? AnsibleDesign.darkPaperElev : AnsibleDesign.paperElev;
        final fg = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
        final border =
            dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
        final label = dark ? 'INK · DARK' : 'PAPER · LIGHT';

        return GestureDetector(
          onTap: controller.toggle,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border, width: 0.5),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 10,
                letterSpacing: 1.2,
                color: fg,
                height: 1,
              ),
            ),
          ),
        );
      },
    );
  }
}
