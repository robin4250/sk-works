import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device review home header and attention behavior are restored', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains('_identity.companyName'));
    expect(app, contains('_identity.displayName'));
    expect(app, contains('now.year'));
    expect(app, contains("'背景・ヘッダー・フッター設定'"));

    expect(home, contains('AnimationController'));
    expect(home, contains('repeat(reverse: true)'));
    expect(home, contains("begin: 0.45"));
    expect(home, contains("'要対応'"));
  });

  test('three and four column home buttons are not vertically elongated', () {
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(home, contains('3 => 1.12'));
    expect(home, contains('_ => 1.05'));
  });

  test('daily report uses the same home shortcut grid as management items', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("key: 'daily_report'"));
    expect(app, contains('HomeShortcut(item.key, item.label, item.icon)'));
    expect(home, contains('for (final shortcut in shortcuts)'));
    expect(home, isNot(contains("'日報の入力・サイン・印刷を確認'")));
  });

  test('all visible menu items can become home buttons and reorder by long press', () {
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(app, contains('this.homeEligible = true'));
    expect(app, contains('ReorderableListView.builder'));
    expect(app, contains('buildDefaultDragHandles: true'));
    expect(app, contains('onReorderItem: _reorderHomeAction'));
    expect(app, contains('長押しして上下へドラッグ'));
    expect(app, contains("label: '背景・ヘッダー・フッター設定'"));
  });

  test('all route headers and root footer react to vertical scroll', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final chrome =
        File('lib/widgets/sko_scroll_chrome.dart').readAsStringSync();

    expect(app, contains('SkoGlobalScrollChrome'));
    expect(app, contains('SkoScrollChromeController.visible.addListener'));
    expect(app, contains("height: _chromeVisible ? 88 : 0"));

    expect(chrome, contains('NotificationListener<ScrollNotification>'));
    expect(chrome, contains('toolbarHeight: visible ? kToolbarHeight : 0'));
    expect(chrome, contains('delta > 2'));
    expect(chrome, contains('delta < -2'));
  });
  test('attendance linkage survives optional vehicle route lookup failures', () {
    final repository = File(
      'lib/features/attendance/attendance_verification_repository.dart',
    ).readAsStringSync();
    final grant = File(
      'supabase/migrations/'
      '20261002091236_fix_vehicle_route_rls_helper_execute.sql',
    ).readAsStringSync();

    expect(repository, contains("Map<String, dynamic>? selection"));
    expect(grant, contains('private.can_manage_vehicle_routes(uuid,text)'));
    expect(grant, contains('supabase_storage_admin'));
  });

  test('management map covers sites customers partners and workers in Google Maps', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final page = File('lib/features/sites/site_map_page.dart').readAsStringSync();
    final repository =
        File('lib/features/sites/site_map_repository.dart').readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20261002091418_extend_site_map_management_directory.sql',
    ).readAsStringSync();

    expect(app, contains("key: 'site_map'"));
    expect(app, contains("label: '現場マップ'"));
    expect(page, contains("'www.google.com'"));
    expect(page, contains("'/maps/search/'"));
    expect(page, contains("'取引会社'"));
    expect(page, contains("'下請け会社'"));
    expect(page, contains("'最新の打刻位置'"));
    expect(repository, contains("customers: rows('customers')"));
    expect(repository, contains("partners: rows('partners')"));
    expect(migration, contains("'customers',v_customers"));
    expect(migration, contains("'partners',v_partners"));
  });
}
