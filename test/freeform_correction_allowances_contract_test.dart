import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance correction uses freely addable allowance names', () {
    final page = File('lib/features/attendance/bulk_attendance_correction_page.dart').readAsStringSync();
    final repo = File('lib/features/attendance/attendance_correction_repository.dart').readAsStringSync();
    expect(page, contains("'手当を追加'"));
    expect(page, contains('allowanceControllers.add'));
    expect(page, contains('allowanceControllers.removeAt'));
    expect(page, contains("'allowanceNames': allowanceNames"));
    expect(repo, contains("'allowance_names'"));
    expect(repo, contains('allowanceNames'));
    expect(page, isNot(contains("suffixText: '円'")));
  });
}
