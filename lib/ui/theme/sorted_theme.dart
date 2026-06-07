import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sorted's "warm ledger" design system.
///
/// Palette and type are chosen to be visually distinct from Splitwise (no
/// signature greens, no Open Sans). Numbers use Fraunces tabular figures so
/// money columns align cleanly in lists.
class SortedTheme {
  SortedTheme._();

  // Brand palette
  static const Color teal = Color(0xFF0E7C66);
  static const Color tealDeep = Color(0xFF0B5E4D);
  static const Color amber = Color(0xFFF4A259);
  static const Color clay = Color(0xFFB45355);
  static const Color paper = Color(0xFFFBFAF6);
  static const Color ink = Color(0xFF11151A);
  static const Color mist = Color(0xFFE9E5DC);
  static const Color dim = Color(0xFF6B6F75);

  // Grey theme palette
  static const Color greyScaffold = Color(0xFFF0F0F0);
  static const Color greyCard = Color(0xFFFFFFFF);
  static const Color greyBorder = Color(0xFFDEDEDE);

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.light,
      primary: teal,
      secondary: amber,
      surface: paper,
      error: clay,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      textTheme: _buildTextTheme(base.textTheme, ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: mist),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: paper,
        elevation: 2,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: mist),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: mist),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: paper,
        selectedItemColor: teal,
        unselectedItemColor: dim,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: const DividerThemeData(color: mist, thickness: 1, space: 1),
    );
  }

  static ThemeData grey() {
    final base = ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.light,
      primary: teal,
      secondary: amber,
      surface: greyScaffold,
      error: clay,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: greyScaffold,
      textTheme: _buildTextTheme(base.textTheme, ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: greyScaffold,
        foregroundColor: ink,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: greyCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: greyBorder),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: greyCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: greyBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: greyBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: teal, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: greyScaffold,
        selectedItemColor: teal,
        unselectedItemColor: dim,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme:
          const DividerThemeData(color: greyBorder, thickness: 1, space: 1),
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    const darkSurface = Color(0xFF11151A);
    const darkSurfaceAlt = Color(0xFF1A1F26);
    const darkBorder = Color(0xFF252B33);
    const darkTeal = Color(0xFF2BA68A);

    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.dark,
      primary: darkTeal,
      secondary: amber,
      surface: darkSurface,
      error: clay,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: darkSurface,
      textTheme: _buildTextTheme(base.textTheme, paper),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: paper,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: darkSurfaceAlt,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkTeal,
        foregroundColor: darkSurface,
        elevation: 2,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkTeal, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: darkTeal,
        unselectedItemColor: Color(0xFF7A828D),
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
    );
  }

  // ── Context-aware semantic helpers ──────────────────────────────────────

  /// Subdued text / icon colour — medium emphasis on the current surface.
  static Color dimOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  /// Card / container fill — one step above the scaffold surface.
  static Color cardFillOf(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;

  /// Subtle border / separator colour that adapts to the current brightness.
  static Color borderOf(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  static TextTheme _buildTextTheme(TextTheme base, Color onSurface) {
    final inter = GoogleFonts.interTextTheme(base).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    final fraunces = GoogleFonts.fraunces(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: onSurface,
    );

    return inter.copyWith(
      displayLarge: fraunces.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w600,
      ),
      displayMedium: fraunces.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
      ),
      displaySmall: fraunces.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: fraunces.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Typography helper for money values — always tabular.
TextStyle amountStyle(BuildContext context, {bool positive = true}) {
  final scheme = Theme.of(context).colorScheme;
  return GoogleFonts.fraunces(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: positive ? scheme.primary : SortedTheme.clay,
  );
}
