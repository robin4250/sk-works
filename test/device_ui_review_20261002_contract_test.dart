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
    expect(app, contains('onReorder: _reorderHomeAction'));
    expect(app, contains('長押しして上下へドラッグ'));
    expect(app, contains("label: '背景・ヘッダー・フッター設定'"));
  });

  test('root header and footer react to vertical scroll', () {
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(app, contains('NotificationListener<ScrollNotification>'));
    expect(app, contains('_handleRootScroll'));
    expect(app, contains('_chromeVisible = false'));
    expect(app, contains('_chromeVisible = true'));
    expect(app, contains("height: _chromeVisible ? 80 : 0"));
  });
}
