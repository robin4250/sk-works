import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class PersonalAppearanceSettings {
  const PersonalAppearanceSettings({
    this.homeWallpaperBase64,
    this.wallpaperOpacity = 100,
    this.buttonOpacity = 100,
    this.cardOpacity = 100,
    this.headerOpacity = 100,
    this.footerOpacity = 100,
  });

  final String? homeWallpaperBase64;
  final int wallpaperOpacity;
  final int buttonOpacity;
  final int cardOpacity;
  final int headerOpacity;
  final int footerOpacity;

  double get wallpaperAlpha => _alpha(wallpaperOpacity);
  double get buttonAlpha => _alpha(buttonOpacity);
  double get cardAlpha => _alpha(cardOpacity);
  double get headerAlpha => _alpha(headerOpacity);
  double get footerAlpha => _alpha(footerOpacity);

  Uint8List? get wallpaperBytes {
    final value = homeWallpaperBase64;
    if (value == null || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  PersonalAppearanceSettings copyWith({
    String? homeWallpaperBase64,
    bool clearWallpaper = false,
    int? wallpaperOpacity,
    int? buttonOpacity,
    int? cardOpacity,
    int? headerOpacity,
    int? footerOpacity,
  }) {
    return PersonalAppearanceSettings(
      homeWallpaperBase64:
          clearWallpaper ? null : homeWallpaperBase64 ?? this.homeWallpaperBase64,
      wallpaperOpacity: _percent(wallpaperOpacity ?? this.wallpaperOpacity),
      buttonOpacity: _percent(buttonOpacity ?? this.buttonOpacity),
      cardOpacity: _percent(cardOpacity ?? this.cardOpacity),
      headerOpacity: _percent(headerOpacity ?? this.headerOpacity),
      footerOpacity: _percent(footerOpacity ?? this.footerOpacity),
    );
  }

  static int _percent(int value) => value.clamp(1, 100);
  static double _alpha(int value) => _percent(value) / 100.0;
}

class PersonalAppearancePreferences {
  const PersonalAppearancePreferences._();

  static String _prefix(String userId) => 'sko_personal_appearance_v1_$userId';

  static Future<PersonalAppearanceSettings> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _prefix(userId);
    return PersonalAppearanceSettings(
      homeWallpaperBase64: prefs.getString('${prefix}_wallpaper'),
      wallpaperOpacity: (prefs.getInt('${prefix}_wallpaper_opacity') ?? 100)
          .clamp(1, 100),
      buttonOpacity:
          (prefs.getInt('${prefix}_button_opacity') ?? 100).clamp(1, 100),
      cardOpacity:
          (prefs.getInt('${prefix}_card_opacity') ?? 100).clamp(1, 100),
      headerOpacity:
          (prefs.getInt('${prefix}_header_opacity') ?? 100).clamp(1, 100),
      footerOpacity:
          (prefs.getInt('${prefix}_footer_opacity') ?? 100).clamp(1, 100),
    );
  }

  static Future<void> save(
    String userId,
    PersonalAppearanceSettings value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = _prefix(userId);
    final wallpaper = value.homeWallpaperBase64;
    if (wallpaper == null || wallpaper.isEmpty) {
      await prefs.remove('${prefix}_wallpaper');
    } else {
      await prefs.setString('${prefix}_wallpaper', wallpaper);
    }
    await prefs.setInt(
      '${prefix}_wallpaper_opacity',
      value.wallpaperOpacity.clamp(1, 100),
    );
    await prefs.setInt(
      '${prefix}_button_opacity',
      value.buttonOpacity.clamp(1, 100),
    );
    await prefs.setInt(
      '${prefix}_card_opacity',
      value.cardOpacity.clamp(1, 100),
    );
    await prefs.setInt(
      '${prefix}_header_opacity',
      value.headerOpacity.clamp(1, 100),
    );
    await prefs.setInt(
      '${prefix}_footer_opacity',
      value.footerOpacity.clamp(1, 100),
    );
  }

  static String encodeWallpaper(Uint8List bytes) => base64Encode(bytes);
}
