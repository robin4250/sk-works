import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu and home layout share one permission-aware registry', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(File('lib/features/home/employee_resources_page.dart').readAsStringSync(), contains("('people', '社員データ'"));
    expect(app, isNot(contains("label: '人員'")));
    expect(app, contains("SkoLanguageController.tr('管理者・サブ管理者・一般・閲覧権限')"));
    expect(app, contains("sko_home_hidden_actions"));
    expect(app, contains("item.homeEligible && !_homeActionHidden(item.key)"));
    expect(app, contains("bool _homeActionHidden(String key) => key == 'friends'"));
    expect(app, contains("_friendHomeActor != _currentHomeActor || !_friendHomeVisible"));
    expect(app, contains(": _hiddenHomeActionKeys.contains(key)"));
    expect(app, contains("final items = _menuItems;"));
    expect(app, contains("ホームとメニューを同じ一覧で管理します"));
    expect(app, contains("SkoLanguageController.tr('1列')"));
    expect(app, contains("SkoLanguageController.tr('4列')"));
    expect(app, contains("case 'company_deliveries':"));
    expect(app, isNot(contains("key: 'company_deliveries'")));
    expect(app, contains('HomeShortcut('));
    expect(home, contains('for (final shortcut in shortcuts)'));
    expect(home, contains('shortcut.access'));
  });
}
