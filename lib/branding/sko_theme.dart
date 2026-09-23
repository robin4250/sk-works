import 'package:flutter/material.dart';

/// Central SKO design tokens.
///
/// Change the colors in this file to update the app-wide look.
/// Most screens inherit these values through ThemeData.
class SkoTheme {
  const SkoTheme._();

  // Brand
  static const Color brand = Color(0xFF0D5DCC);
  static const Color brandDark = Color(0xFF083F8F);
  static const Color brandLight = Color(0xFF5AA7FF);

  // Surfaces
  static const Color background = Color(0xFFF4F7FB);
  static const Color surface = Colors.white;
  static const Color surfaceSoft = Color(0xFFF8FAFD);

  // Text
  static const Color textPrimary = Color(0xFF172033);
  static const Color textSecondary = Color(0xFF60758A);

  // Icons
  static const Color iconPrimary = Color(0xFF244A72);
  static const Color iconSecondary = Color(0xFF60758A);
  static const Color inputIcon = Color(0xFF42698E);

  // Borders
  static const Color border = Color(0xFFC7D2DF);
  static const Color borderStrong = Color(0xFF9FB0C2);

  // Status colors
  static const Color success = Color(0xFF218A55);
  static const Color warning = Color(0xFFD98300);
  static const Color danger = Color(0xFFC73939);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: brand,
      surface: surface,
      error: danger,
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
    );

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme
          .apply(
            bodyColor: textPrimary,
            displayColor: textPrimary,
          )
          .copyWith(
            headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
            titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
            titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
      iconTheme: const IconThemeData(
        size: 24,
        color: iconPrimary,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: iconPrimary),
        actionsIconTheme: IconThemeData(color: iconPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        prefixIconColor: inputIcon,
        suffixIconColor: inputIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: brand, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandDark,
          minimumSize: const Size(0, 50),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          side: const BorderSide(color: borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: iconPrimary,
        textColor: textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? brandDark
                : textSecondary,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w900
                : FontWeight.w700,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 25,
            color: states.contains(WidgetState.selected)
                ? brand
                : iconSecondary,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      dividerColor: border,
    );
  }
}
