import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin home keeps top attendance status entry without duplicate management tile', () {
    final source =
        File('lib/features/home/friendly_home_content.dart').readAsStringSync();

    expect(source, contains("'本日の出勤'"));
    expect(source, contains("'出勤状況を確認'"));
    expect(source, contains("onOpen('attendance_today')"));

    expect(source, isNot(contains("'出勤・人区管理'")));
    expect(
      RegExp(r"onOpen\('attendance_today'\)").allMatches(source).length,
      equals(1),
    );
    expect(
      RegExp(r"onOpen\('attendance'\)").allMatches(source).length,
      equals(0),
    );

    expect(source, contains("onOpen('clock_in')"));
    expect(source, contains("onOpen('clock_out')"));
  });
}
