import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance sheet and today attendance stay on separate routes', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final home =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(
      app,
      contains(
        "key == 'attendance_today'",
      ),
    );
    expect(
      app,
      contains(
        'builder: (_) => const AttendanceCloudPage()',
      ),
    );

    final pagesStart = app.indexOf('final pages = <Widget>[');
    expect(pagesStart, greaterThanOrEqualTo(0));
    final pagesBlock = app.substring(
      pagesStart,
      app.indexOf('return Scaffold(', pagesStart),
    );
    expect(pagesBlock, contains('const WorkerAttendanceSheetPage()'));
    expect(
      pagesBlock,
      isNot(contains(
        "? const AttendanceCloudPage()\n              : const WorkerAttendanceSheetPage()",
      )),
    );

    expect(
      home,
      contains("onPressed: () => onOpen('attendance_today')"),
    );
    expect(
      home,
      isNot(contains(
        "onPressed: () => onOpen('attendance'),\n                  icon: const Icon(Icons.groups_outlined)",
      )),
    );
  });
}
