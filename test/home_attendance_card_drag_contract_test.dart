import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full-size attendance home cards keep size and support drag reorder', () {
    final home = File(
      'lib/features/home/friendly_home_content.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(home, contains("_DraggableHomeCard("));
    expect(home, contains("keyName: 'attendance_verify'"));
    expect(home, contains("keyName: 'attendance_today'"));
    expect(home, contains('LongPressDraggable<String>'));
    expect(home, contains('DragTarget<String>'));
    expect(home, contains('_PersonalAttendanceCard('));
    expect(home, contains('_TodayAttendanceHomeCard('));

    // These two remain full-width cards and are not converted into grid tiles.
    expect(
      RegExp(
        r"_HomeAction\(\s*'attendance_verify'",
        multiLine: true,
      ).hasMatch(home),
      isFalse,
    );
    expect(
      RegExp(
        r"_HomeAction\(\s*'attendance_today'",
        multiLine: true,
      ).hasMatch(home),
      isFalse,
    );

    expect(app, contains("key: 'attendance_verify'"));
    expect(app, contains("key: 'attendance_today'"));
    expect(app, contains('_reorderHomeActionByKey'));
    expect(app, contains('newIndex > items.length'));
    expect(app, contains('if (newIndex > oldIndex) newIndex -= 1'));
    expect(app, contains('newIndex.clamp(0, ordered.length)'));
    expect(app, contains("prefs.setStringList('sko_home_action_order'"));
  });
}
