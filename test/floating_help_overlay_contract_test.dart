import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('floating help is global movable and enabled by default', () {
    final controller = File(
      'lib/features/help/floating_help_controller.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/features/help/floating_help_overlay.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(controller, contains("ValueNotifier<bool>(true)"));
    expect(controller, contains("ValueNotifier<double>(1.0)"));
    expect(controller, contains("sko_floating_help_enabled"));
    expect(controller, contains("sko_floating_help_x"));
    expect(controller, contains("sko_floating_help_y"));
    expect(overlay, contains("footerClearance = 78.0"));
    expect(overlay, contains("MediaQuery.viewInsetsOf(context).bottom"));
    expect(overlay, contains("keyboardHeight > 0"));
    expect(overlay, contains("onLongPressStart"));
    expect(overlay, contains("onLongPressMoveUpdate"));
    expect(overlay, contains("onLongPressEnd"));
    expect(overlay, contains("何かお困りですか？"));
    expect(app, contains("const FloatingHelpOverlay()"));
  });

  test('settings exposes floating help on off guidance', () {
    final settings =
        File('lib/features/settings/settings_page.dart').readAsStringSync();
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();

    expect(settings, contains("SwitchListTile"));
    expect(settings, contains("SkoLanguageController.tr('フローティングヘルプ')"));
    expect(settings, contains("FloatingHelpController.setEnabled"));
    expect(
      settings,
      contains('ボタンは長押しで好きな位置へ移動できます。'),
    );
    expect(english, contains("'フローティングヘルプ': 'Floating Help'"));
  });

  test('floating help uses existing help dictionary and current feature context', () {
    final overlay = File(
      'lib/features/help/floating_help_overlay.dart',
    ).readAsStringSync();
    final controller = File(
      'lib/features/help/floating_help_controller.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(controller, contains("MenuHelpCatalog.visibleFor"));
    expect(controller, contains("currentFeatureKey"));
    expect(overlay, contains("Search by page, feature, or action."));
    expect(app, contains("FloatingHelpController.setContext"));
  });
}
