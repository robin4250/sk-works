import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home layout controls persist columns and ordering without moving fixed cards', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(app, contains("sko_home_grid_columns"));
    expect(app, contains("sko_home_action_order"));
    expect(app, contains("ButtonSegment(value: 1"));
    expect(app, contains("ButtonSegment(value: 2"));
    expect(app, contains("ButtonSegment(value: 3"));
    expect(app, contains("ButtonSegment(value: 4"));
    expect(app, contains("'並び順'"));
    expect(app, contains("keyboard_arrow_up"));
    expect(app, contains("keyboard_arrow_down"));

    expect(home, contains("final int gridColumns"));
    expect(home, contains("final List<String> actionOrder"));
    expect(home, contains("crossAxisCount: columnCount"));
    expect(home, contains("ordered.sort"));

    final gridClass = home.indexOf('class _ActionGrid');
    final attentionClass = home.indexOf('class _RequiredDocumentAttentionCard');
    final personalClass = home.indexOf('class _PersonalAttendanceCard');
    final adminClass = home.indexOf('class _AdminHome');
    expect(gridClass, greaterThan(adminClass));
    expect(attentionClass, lessThan(gridClass));
    expect(personalClass, lessThan(gridClass));

    expect(
      app,
      contains(
        '通常の小ボタンだけを変更します。要対応・本日の勤務報告・本日の出勤は固定です。',
      ),
    );
  });
}
