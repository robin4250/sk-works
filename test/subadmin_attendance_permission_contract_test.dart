import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance navigation follows can_manage_attendance permission', () {
    final source = File('lib/app_v2.dart').readAsStringSync();

    expect(
      RegExp(r"_identity\.can\('can_manage_attendance'\)[\s\S]*?AttendanceCloudPage\(\)[\s\S]*?WorkerAttendanceSheetPage\(\)")
          .allMatches(source)
          .length,
      greaterThanOrEqualTo(1),
    );
    expect(
      RegExp(r"if \(key == 'attendance_today'\)[\s\S]*?TodayAttendancePage\(\)")
          .hasMatch(source),
      isTrue,
    );
    final todayBlock = RegExp(
      r"if \(key == 'attendance_today'\)[\s\S]*?return;\n    }",
    ).firstMatch(source)?.group(0) ?? '';
    expect(
      todayBlock,
      isNot(contains("_identity.can('can_manage_attendance')")),
    );
    expect(
      source,
      isNot(contains("_isAdmin\n              ? const AttendanceCloudPage()")),
    );
  });
}
