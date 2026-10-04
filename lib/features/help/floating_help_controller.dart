import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'manual_content.dart';
import 'menu_help_catalog.dart';

class FloatingHelpController {
  FloatingHelpController._();

  static const _enabledKey = 'sko_floating_help_enabled';
  static const _xKey = 'sko_floating_help_x';
  static const _yKey = 'sko_floating_help_y';

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  static final ValueNotifier<double> xFraction = ValueNotifier<double>(0.88);
  static final ValueNotifier<double> yFraction = ValueNotifier<double>(0.62);
  static final ValueNotifier<String?> currentFeatureKey =
      ValueNotifier<String?>(null);
  static final ValueNotifier<ManualRole> role =
      ValueNotifier<ManualRole>(ManualRole.general);
  static final ValueNotifier<Set<String>> visibleFeatureKeys =
      ValueNotifier<Set<String>>(<String>{});

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_enabledKey) ?? true;
    xFraction.value = (prefs.getDouble(_xKey) ?? 0.88).clamp(0.0, 1.0);
    yFraction.value = (prefs.getDouble(_yKey) ?? 0.62).clamp(0.0, 1.0);
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<void> savePosition({
    required double x,
    required double y,
  }) async {
    xFraction.value = x.clamp(0.0, 1.0);
    yFraction.value = y.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_xKey, xFraction.value);
    await prefs.setDouble(_yKey, yFraction.value);
  }

  static void setContext({
    String? featureKey,
    ManualRole? currentRole,
    Set<String>? visibleKeys,
  }) {
    if (featureKey != null) currentFeatureKey.value = featureKey;
    if (currentRole != null) role.value = currentRole;
    if (visibleKeys != null) {
      visibleFeatureKeys.value = Set<String>.from(visibleKeys);
    }
  }

  static MenuHelpItem? currentHelpItem() {
    final key = currentFeatureKey.value;
    if (key == null) return null;
    for (final item in MenuHelpCatalog.items) {
      if (item.key == key && item.roles.contains(role.value)) return item;
    }
    return null;
  }

  static List<MenuHelpItem> searchableItems() {
    final visible = visibleFeatureKeys.value;
    return MenuHelpCatalog.visibleFor(
      role: role.value,
      visibleKeys: visible.isEmpty ? null : visible,
    );
  }
}
