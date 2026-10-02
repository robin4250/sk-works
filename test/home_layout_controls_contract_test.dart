import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home layout controls persist columns and long-press ordering', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("sko_home_grid_columns"));
    expect(app, contains("sko_home_action_order"));
    expect(app, contains("ButtonSegment(value: 1"));
    expect(app, contains("ButtonSegment(value: 2"));
    expect(app, contains("ButtonSegment(value: 3"));
    expect(app, contains("ButtonSegment(value: 4"));
    expect(app, contains('ホーム表示・並び順・権限'));
    expect(app, contains('ReorderableListView.builder'));
    expect(app, contains('onReorderItem: _reorderHomeAction'));
    expect(app, contains('長押しして上下へドラッグ'));

    expect(home, contains("final int gridColumns"));
    expect(home, contains("final List<String> actionOrder"));
    expect(home, contains("crossAxisCount: columnCount"));
    expect(home, contains("ordered.sort"));
    expect(home, contains('3 => 1.12'));
    expect(home, contains('_ => 1.05'));

    expect(
      app,
      contains('ホームとメニューを同じ一覧で管理します。'),
    );
  });
}
