import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu and home layout share one permission-aware registry', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("SkoLanguageController.tr('社員')"));
    expect(app, isNot(contains("label: '人員'")));
    expect(app, contains("SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限')"));
    expect(app, contains("sko_home_hidden_actions"));
    expect(app, contains("item.homeEligible && !_hiddenHomeActionKeys.contains(item.key)"));
    expect(app, contains("final items = _menuItems;"));
    expect(app, contains("ホームとメニューを同じ一覧で管理します"));
    expect(app, contains("SkoLanguageController.tr('1列')"));
    expect(app, contains("SkoLanguageController.tr('4列')"));
    expect(app, contains("SkoLanguageController.tr('協力会社')"));
    expect(app, contains('HomeShortcut('));
    expect(home, contains('for (final shortcut in shortcuts)'));
    expect(home, contains('shortcut.access'));
  });
}
