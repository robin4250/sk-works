import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('today attendance shows yesterday-first one month history', () {
    final page = File('lib/features/attendance/today_attendance_page.dart').readAsStringSync();
    final repo = File('lib/features/attendance/today_attendance_repository.dart').readAsStringSync();
    expect(page, contains("'過去1か月'"));
    expect(page, contains('_HistoryDayCard'));
    expect(page, contains('diff >= 1 && diff <= 7'));
    expect(repo, contains('for (var offset = 1; offset <= 30; offset++)'));
    expect(repo, contains('todayStart.subtract(Duration(days: offset))'));
    expect(page, contains('partnerTab: _tabIndex == 1'));
  });
}
