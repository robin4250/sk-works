import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance navigation follows can_manage_attendance permission', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      source,
      contains("if (key == 'attendance_today')"),
    );
    expect(
      source,
      contains("if (!_identity.can('can_manage_attendance'))"),
    );
    expect(
      source,
      contains('builder: (_) => const TodayAttendancePage()'),
    );

    final pagesStart = source.indexOf('final pages = <Widget>[');
    expect(pagesStart, greaterThanOrEqualTo(0));
    final pagesEnd = source.indexOf('return Scaffold(', pagesStart);
    final pages = source.substring(pagesStart, pagesEnd);
    expect(pages, contains('const WorkerAttendanceSheetPage()'));
    expect(pages, isNot(contains('const AttendanceCloudPage()')));

    expect(
      source,
      isNot(contains("_isAdmin\n              ? const AttendanceCloudPage()")),
    );
  });
}
