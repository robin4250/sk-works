import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu and home layout share one permission-aware registry', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("SkoLanguageController.tr('社員')"));
    expect(app, isNot(contains("label: '人員'")));
    expect(app, contains("accessLabel: '管理者・サブ管理者・一般・閲覧権限'"));
    expect(app, contains("sko_home_hidden_actions"));
    expect(app, contains("item.homeEligible && !_hiddenHomeActionKeys.contains(item.key)"));
    expect(app, contains("final items = _menuItems;"));
    expect(app, contains("ホームとメニューを同じ一覧で管理します"));
    expect(app, contains("ButtonSegment(value: 1, label: Text('1列'))"));
    expect(app, contains("ButtonSegment(value: 4, label: Text('4列'))"));
    expect(app, contains("label: '協力会社'"));
    expect(app, contains('HomeShortcut(item.key, item.label, item.icon)'));
    expect(home, contains('for (final shortcut in shortcuts)'));
    expect(home, contains('_shortcutAccess(shortcut.key)'));
  });
}
