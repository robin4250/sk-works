import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SkoPalette {
  const SkoPalette({
    required this.key,
    required this.label,
    required this.brand,
    required this.brandDark,
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.inputIcon,
    required this.border,
    required this.borderStrong,
  });

  final String key;
  final String label;
  final Color brand;
  final Color brandDark;
  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color inputIcon;
  final Color border;
  final Color borderStrong;
}

/// Central SKO design system.
///
/// App-wide colors are controlled here. SettingsPage switches between the
/// palettes below and the selected palette is stored on the device.
class SkoTheme {
  const SkoTheme._();

  static const palettes = <SkoPalette>[
    SkoPalette(
      key: 'sko_blue',
      label: 'SKOブルー',
      brand: Color(0xFF0D5DCC),
      brandDark: Color(0xFF083F8F),
      background: Color(0xFFF4F7FB),
      surface: Colors.white,
      textPrimary: Color(0xFF172033),
      textSecondary: Color(0xFF60758A),
      iconPrimary: Color(0xFF244A72),
      iconSecondary: Color(0xFF60758A),
      inputIcon: Color(0xFF42698E),
      border: Color(0xFFC7D2DF),
      borderStrong: Color(0xFF9FB0C2),
    ),
    SkoPalette(
      key: 'navy',
      label: 'ネイビー',
      brand: Color(0xFF173B57),
      brandDark: Color(0xFF0F2A3F),
      background: Color(0xFFF4F6F8),
      surface: Colors.white,
      textPrimary: Color(0xFF17212A),
      textSecondary: Color(0xFF61717E),
      iconPrimary: Color(0xFF234C68),
      iconSecondary: Color(0xFF61717E),
      inputIcon: Color(0xFF3E647D),
      border: Color(0xFFC8D1D8),
      borderStrong: Color(0xFF9FAEB8),
    ),
    SkoPalette(
      key: 'green',
      label: 'グリーン',
      brand: Color(0xFF147D64),
      brandDark: Color(0xFF0D5A48),
      background: Color(0xFFF3F8F6),
      surface: Colors.white,
      textPrimary: Color(0xFF173029),
      textSecondary: Color(0xFF62776F),
      iconPrimary: Color(0xFF216A59),
      iconSecondary: Color(0xFF62776F),
      inputIcon: Color(0xFF3B7768),
      border: Color(0xFFC6D7D1),
      borderStrong: Color(0xFF9AB7AD),
    ),
    SkoPalette(
      key: 'orange',
      label: 'オレンジ',
      brand: Color(0xFFC56818),
      brandDark: Color(0xFF934B0E),
      background: Color(0xFFFBF7F2),
      surface: Colors.white,
      textPrimary: Color(0xFF312318),
      textSecondary: Color(0xFF7B6B5D),
      iconPrimary: Color(0xFF9D5317),
      iconSecondary: Color(0xFF7B6B5D),
      inputIcon: Color(0xFFA86834),
      border: Color(0xFFDED0C2),
      borderStrong: Color(0xFFC0AA94),
    ),
    SkoPalette(
      key: 'purple',
      label: 'パープル',
      brand: Color(0xFF6D4BC3),
      brandDark: Color(0xFF4E3198),
      background: Color(0xFFF7F5FB),
      surface: Colors.white,
      textPrimary: Color(0xFF261B36),
      textSecondary: Color(0xFF746985),
      iconPrimary: Color(0xFF594094),
      iconSecondary: Color(0xFF746985),
      inputIcon: Color(0xFF705AA0),
      border: Color(0xFFD4CDDE),
      borderStrong: Color(0xFFB2A7C0),
    ),
    SkoPalette(
      key: 'charcoal',
      label: 'チャコール',
      brand: Color(0xFF465463),
      brandDark: Color(0xFF303A44),
      background: Color(0xFFF5F6F7),
      surface: Colors.white,
      textPrimary: Color(0xFF1D242B),
      textSecondary: Color(0xFF68737D),
      iconPrimary: Color(0xFF455463),
      iconSecondary: Color(0xFF68737D),
      inputIcon: Color(0xFF5F6E7B),
      border: Color(0xFFCDD3D8),
      borderStrong: Color(0xFFA7B0B8),
    ),
  ];

  static const success = Color(0xFF218A55);
  static const warning = Color(0xFFD98300);
  static const danger = Color(0xFFC73939);

  static SkoPalette byKey(String key) {
    return palettes.firstWhere(
      (palette) => palette.key == key,
      orElse: () => palettes.first,
    );
  }

  static ThemeData light(SkoPalette palette) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.brand,
      brightness: Brightness.light,
    ).copyWith(
      primary: palette.brand,
      surface: palette.surface,
      error: danger,
    );

    final baseTheme = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: palette.background,
    );

    return baseTheme.copyWith(
      textTheme: baseTheme.textTheme
          .apply(
            bodyColor: palette.textPrimary,
            displayColor: palette.textPrimary,
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
      iconTheme: IconThemeData(
        size: 24,
        color: palette.iconPrimary,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: palette.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        iconTheme: IconThemeData(color: palette.iconPrimary),
        actionsIconTheme: IconThemeData(color: palette.iconPrimary),
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        prefixIconColor: palette.inputIcon,
        suffixIconColor: palette.inputIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.brand, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.brand,
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
          foregroundColor: palette.brandDark,
          minimumSize: const Size(0, 50),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          side: BorderSide(color: palette.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.brandDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.iconPrimary,
        textColor: palette.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: palette.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? palette.brandDark
                : palette.textSecondary,
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
                ? palette.brand
                : palette.iconSecondary,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.brand,
        foregroundColor: Colors.white,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      dividerColor: palette.border,
    );
  }
}

class SkoThemeController {
  const SkoThemeController._();

  static const _prefsKey = 'sko_theme_palette_v1';
  static final ValueNotifier<SkoPalette> palette =
      ValueNotifier<SkoPalette>(SkoTheme.palettes.first);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_prefsKey) ?? SkoTheme.palettes.first.key;
    palette.value = SkoTheme.byKey(key);
  }

  static Future<void> setPalette(String key) async {
    final next = SkoTheme.byKey(key);
    if (palette.value.key == next.key) return;
    palette.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.key);
  }
}
