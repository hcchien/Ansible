import 'package:flutter/material.dart';

import '../l10n/app_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Elix Design System — "Forest Letter".
// Canonical source: Elix Brand System.html plus the Forest Letter tokens in the
// 2026-08-30 12:30 handoff. Mist + Ink carry the product; lavender is the
// identity/CTA signal, sky blue is secondary trust, and yellow marks energy.
// ─────────────────────────────────────────────────────────────────────────────

class AnsibleDesign {
  static const brandName = 'Elix';

  // ── Shape & rhythm ───────────────────────────────────────────────────────
  // Keep these values centralized. The handoff relies on a restrained set of
  // radii and hairlines; one-off Material defaults make the screens drift back
  // toward a generic app even when the palette is correct.
  static const hairline = 0.5;
  static const cardRadius = 12.0;
  static const compactRadius = 8.0;
  static const pageGutter = 22.0;
  static const sectionGap = 18.0;

  // ── Light (Mist — canonical) ──────────────────────────────────────────────
  static const paper = Color(0xFFF4F3EC);
  static const paperElev = Color(0xFFECEAE0);
  static const paperDeep = Color(0xFFE2DFD2);
  static const paperWhite = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2A2A0A);
  static const inkMuted = Color(0xFF625F3C);
  static const inkFaint = Color(0xFF9C9974);
  static const rule = Color(0xFFD8D3C4);
  static const ruleSoft = Color(0xFFE6E2D6);
  static const accent = Color(0xFFC9AEEB);
  static const accentSoft = Color(0xFFDCC9F0);
  static const signalSoft = Color(0xFFC7DDF1);
  static const tintSky = Color(0xFFE3EFF8);
  static const tintLavender = Color(0xFFEDE4F7);
  static const tintCitron = Color(0xFFF5F1BE);
  static const spore = accent;
  static const moss = Color(0xFF6FB2E8);
  static const lavender = accent;
  static const highlight = Color(0xFFEBE21C);
  static const navy = Color(0xFF2846A8);
  static const danger = Color(0xFFC0475C);
  static const ember = highlight;
  static const ochre = accent;

  // ── Dark (Pine) ───────────────────────────────────────────────────────────
  static const darkPaper = Color(0xFF17130A);
  static const darkPaperElev = Color(0xFF1F1A0E);
  static const darkPaperDeep = Color(0xFF2A2413);
  static const darkPaperWhite = Color(0xFF1F1A0E);
  static const darkInk = Color(0xFFF4EEDA);
  static const darkInkMuted = Color(0xFFB7AD8E);
  static const darkInkFaint = Color(0xFF726B4F);
  static const darkRule = Color(0xFF362E17);
  static const darkRuleSoft = Color(0xFF221D10);
  static const darkSignalSoft = Color(0xFF36536A);
  static const darkTintSky = Color(0xFF1C2A33);
  static const darkTintLavender = Color(0xFF31283D);
  static const darkTintCitron = Color(0xFF302D12);
  static const darkOchre = Color(0xFFD9C6F2);
  static const darkMoss = Color(0xFF8FC4F5);
  static const darkLavender = darkOchre;
  static const darkHighlight = Color(0xFFF5EE3A);
  static const darkNavy = Color(0xFF5C82E0);
  static const darkEmber = darkHighlight;

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

  static TextTheme _editorialTextTheme(
    TextTheme base, {
    required Color foreground,
    required Color muted,
  }) {
    TextStyle serif(
      TextStyle? style, {
      double? size,
      double? height,
      FontWeight? weight,
      Color? color,
    }) => (style ?? const TextStyle()).copyWith(
      fontFamily: AnsibleDesign.serif,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color ?? foreground,
      letterSpacing: 0,
    );

    TextStyle chrome(TextStyle? style, {Color? color}) =>
        (style ?? const TextStyle()).copyWith(
          fontFamily: AnsibleDesign.sans,
          fontFamilyFallback: fallback,
          color: color ?? foreground,
        );

    return base.copyWith(
      displayLarge: serif(base.displayLarge, weight: FontWeight.w500),
      displayMedium: serif(base.displayMedium, weight: FontWeight.w500),
      displaySmall: serif(
        base.displaySmall,
        size: 28,
        height: 1.2,
        weight: FontWeight.w500,
      ),
      headlineLarge: serif(base.headlineLarge, weight: FontWeight.w500),
      headlineMedium: serif(
        base.headlineMedium,
        size: 28,
        height: 1.2,
        weight: FontWeight.w500,
      ),
      headlineSmall: serif(
        base.headlineSmall,
        size: 22,
        height: 1.3,
        weight: FontWeight.w500,
      ),
      titleLarge: serif(
        base.titleLarge,
        size: 22,
        height: 1.3,
        weight: FontWeight.w500,
      ),
      titleMedium: serif(
        base.titleMedium,
        size: 17,
        height: 1.35,
        weight: FontWeight.w500,
      ),
      titleSmall: serif(
        base.titleSmall,
        size: 15,
        height: 1.4,
        weight: FontWeight.w500,
      ),
      bodyLarge: serif(base.bodyLarge, size: 16, height: 1.7),
      bodyMedium: serif(base.bodyMedium, size: 14.5, height: 1.65),
      bodySmall: serif(base.bodySmall, size: 13.5, height: 1.6, color: muted),
      labelLarge: chrome(base.labelLarge),
      labelMedium: chrome(base.labelMedium, color: muted),
      labelSmall: chrome(base.labelSmall, color: muted),
    );
  }

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
      return selected ? accent : rule;
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      return states.contains(WidgetState.selected) ? accent : rule;
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
      onSecondary: ink,
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
      textTheme: _editorialTextTheme(
        base.textTheme,
        foreground: ink,
        muted: inkMuted,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: mono,
          fontFamilyFallback: fallback,
          color: inkMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.8,
        ),
        shape: Border(
          bottom: BorderSide(color: ruleSoft, width: hairline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: ruleSoft, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paperElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compactRadius),
          borderSide: const BorderSide(color: rule, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compactRadius),
          borderSide: const BorderSide(color: rule, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compactRadius),
          borderSide: const BorderSide(color: accent, width: 1.2),
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
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ink,
        foregroundColor: paper,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(),
      ),
      iconTheme: const IconThemeData(color: inkMuted),
      cardTheme: CardThemeData(
        color: paperWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: rule, width: 0.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: paperElev,
        selectedColor: accentSoft,
        side: const BorderSide(color: rule, width: 0.5),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: inkMuted,
          fontFamily: serif,
          fontSize: 12,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: inkMuted,
        textColor: ink,
        titleTextStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          color: inkMuted,
          fontSize: 12.5,
          height: 1.55,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: ruleSoft,
        indicatorColor: ink,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: ink,
        unselectedLabelColor: inkFaint,
        labelStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          fontSize: 13,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ink,
        linearTrackColor: paperDeep,
        circularTrackColor: paperDeep,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: rule, width: hairline),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : paper,
        ),
        checkColor: const WidgetStatePropertyAll(paper),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : inkFaint,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paperWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: rule, width: 0.5),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paperWhite,
        modalBackgroundColor: paperWhite,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: paper,
        indicatorColor: accentSoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: sans, fontSize: 11.5),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: paper,
        indicatorColor: accentSoft,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: ink),
        unselectedIconTheme: IconThemeData(color: inkFaint),
        selectedLabelTextStyle: TextStyle(fontFamily: sans, color: ink),
        unselectedLabelTextStyle: TextStyle(fontFamily: sans, color: inkFaint),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: const TextStyle(fontFamily: sans, color: paper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      // The Material 3 default uses a very dark unselected track with this
      // colour scheme.  On paper it made ON and OFF settings look almost the
      // same, which is particularly unsafe for consent-bearing controls such
      // as Fediverse publication.  Keep the thumb/track contrast explicit.
      switchTheme: paperSwitchTheme(),
    );
  }

  // ── Dark theme (Ink) ──────────────────────────────────────────────────────
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
      textTheme: _editorialTextTheme(
        base.textTheme,
        foreground: darkInk,
        muted: darkInkMuted,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPaper,
        foregroundColor: darkInk,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: mono,
          fontFamilyFallback: fallback,
          color: darkInkMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.8,
        ),
        shape: Border(
          bottom: BorderSide(color: darkRuleSoft, width: hairline),
        ),
      ),
      dividerTheme: const DividerThemeData(color: darkRuleSoft, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkPaperElev,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compactRadius),
          borderSide: const BorderSide(color: darkRule, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compactRadius),
          borderSide: const BorderSide(color: darkRule, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(compactRadius),
          borderSide: const BorderSide(color: darkOchre, width: 1.2),
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
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkInk,
        foregroundColor: darkPaper,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(),
      ),
      iconTheme: const IconThemeData(color: darkInkMuted),
      cardTheme: CardThemeData(
        color: darkPaperWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: darkRule, width: 0.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: darkPaperElev,
        selectedColor: darkTintLavender,
        side: const BorderSide(color: darkRule, width: 0.5),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: darkInkMuted,
          fontFamily: serif,
          fontSize: 12,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: darkInkMuted,
        textColor: darkInk,
        titleTextStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          color: darkInk,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          color: darkInkMuted,
          fontSize: 12.5,
          height: 1.55,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: darkRuleSoft,
        indicatorColor: darkInk,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: darkInk,
        unselectedLabelColor: darkInkFaint,
        labelStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          fontSize: 13,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkInk,
        linearTrackColor: darkPaperDeep,
        circularTrackColor: darkPaperDeep,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: darkRule, width: hairline),
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? darkInk : darkPaper,
        ),
        checkColor: const WidgetStatePropertyAll(darkPaper),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? darkInk : darkInkFaint,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkPaperWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkRule, width: 0.5),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: serif,
          fontFamilyFallback: fallback,
          color: darkInk,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkPaperWhite,
        modalBackgroundColor: darkPaperWhite,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: darkPaper,
        indicatorColor: darkTintLavender,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: sans, fontSize: 11.5),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: darkPaper,
        indicatorColor: darkTintLavender,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: darkInk),
        unselectedIconTheme: IconThemeData(color: darkInkFaint),
        selectedLabelTextStyle: TextStyle(fontFamily: sans, color: darkInk),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: sans,
          color: darkInkFaint,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkInk,
        contentTextStyle: const TextStyle(fontFamily: sans, color: darkPaper),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return darkPaperDeep;
          return darkPaper;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return darkPaperDeep;
          return states.contains(WidgetState.selected) ? darkOchre : darkRule;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return darkOchre;
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = color ?? (dark ? AnsibleDesign.darkInk : AnsibleDesign.ink);
    return Semantics(
      label: AnsibleDesign.brandName,
      child: ExcludeSemantics(
        child: SizedBox(
          width: fontSize * 2.92,
          height: fontSize,
          child: CustomPaint(
            painter: _ElixWordmarkPainter(
              color: ink,
              accent: dark ? AnsibleDesign.darkOchre : AnsibleDesign.accent,
            ),
          ),
        ),
      ),
    );
  }
}

/// The geometric ELIX wordmark from the handoff. The X is four independent
/// strokes with a diamond-shaped centre gap; the I tittle carries the trust
/// lavender even when the surrounding wordmark is rendered in another colour.
class _ElixWordmarkPainter extends CustomPainter {
  const _ElixWordmarkPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 100;
    canvas.save();
    canvas.scale(scale, scale);

    const sw = 14.0;
    const mid = 43.0;
    const bot = 86.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.butt;

    final e = Path()
      ..moveTo(0, 0)
      ..lineTo(64, 0)
      ..lineTo(64, sw)
      ..lineTo(sw, sw)
      ..lineTo(sw, mid)
      ..lineTo(50, mid)
      ..lineTo(50, mid + sw)
      ..lineTo(sw, mid + sw)
      ..lineTo(sw, bot)
      ..lineTo(64, bot)
      ..lineTo(64, 100)
      ..lineTo(0, 100)
      ..close();
    final l = Path()
      ..moveTo(88, 0)
      ..lineTo(88 + sw, 0)
      ..lineTo(88 + sw, bot)
      ..lineTo(152, bot)
      ..lineTo(152, 100)
      ..lineTo(88, 100)
      ..close();
    final i = Path()
      ..moveTo(176, 23.8)
      ..lineTo(176 + sw, 23.8)
      ..lineTo(176 + sw, 100)
      ..lineTo(176, 100)
      ..close();

    canvas.drawPath(e, fill);
    canvas.drawPath(l, fill);
    canvas.drawPath(i, fill);
    canvas.drawCircle(
      const Offset(183, 8.68),
      8.68,
      Paint()
        ..color = accent
        ..style = PaintingStyle.fill,
    );
    canvas.drawLine(const Offset(214, 0), const Offset(246.7, 43), stroke);
    canvas.drawLine(const Offset(290, 0), const Offset(257.3, 43), stroke);
    canvas.drawLine(const Offset(214, 100), const Offset(246.7, 57), stroke);
    canvas.drawLine(const Offset(290, 100), const Offset(257.3, 57), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ElixWordmarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.accent != accent;
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
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 9 * s;
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rule = dark ? AnsibleDesign.darkRule : AnsibleDesign.rule;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final signal = dark ? AnsibleDesign.darkMoss : AnsibleDesign.spore;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: rule, width: 0.5),
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
              color: dot ?? signal,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: AnsibleDesign.mono,
              fontSize: 11.5,
              color: muted,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AnsibleDesign.darkInk : AnsibleDesign.ink;
    final muted = dark ? AnsibleDesign.darkInkMuted : AnsibleDesign.inkMuted;
    final faint = dark ? AnsibleDesign.darkInkFaint : AnsibleDesign.inkFaint;
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
              style: TextStyle(
                fontFamily: AnsibleDesign.serif,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              en,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 11,
                color: faint,
                letterSpacing: 1.4,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null)
            Text(
              action!,
              style: TextStyle(
                fontFamily: AnsibleDesign.mono,
                fontSize: 10,
                color: muted,
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
        return dark ? AnsibleDesign.darkHighlight : AnsibleDesign.ink;
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
        return (dark ? AnsibleDesign.darkHighlight : AnsibleDesign.highlight)
            .withValues(alpha: 0.22);
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
        return dark ? AnsibleDesign.darkHighlight : AnsibleDesign.ink;
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
          border: Border.all(color: ring, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: AnsibleMark(
            size: 26,
            color: dark ? AnsibleDesign.darkPaper : AnsibleDesign.ink,
          ),
        ),
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
