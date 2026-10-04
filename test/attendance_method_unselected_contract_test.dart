import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance method starts unselected and blocks save until chosen', () {
    final selection = File(
      'lib/features/attendance/attendance_selection_page.dart',
    ).readAsStringSync();
    final verification = File(
      'lib/features/attendance/attendance_verification_page.dart',
    ).readAsStringSync();
    final repository = File(
      'lib/features/attendance/attendance_verification_repository.dart',
    ).readAsStringSync();

    expect(selection, contains("String _mode = 'none';"));
    expect(selection, contains("value: 'none'"));
    expect(selection, contains("Text('未選択')"));
    expect(selection, contains("出勤方法を選択してください"));

    expect(verification, contains("String _mode = 'none';"));
    expect(verification, contains("value: 'none'"));
    expect(verification, contains("出勤方法を選択してください"));

    expect(repository, contains("this.verificationMode = 'none'"));
    expect(repository, contains("'none' => '未選択'"));
    expect(repository, contains("scheduledToday ? 'gps_auto' : 'none'"));
  });
}
