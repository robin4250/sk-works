import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('past bulk attendance uses freely addable allowance names', () {
    final source = File(
      'lib/features/attendance/bulk_attendance_page.dart',
    ).readAsStringSync();
    expect(source, contains("'手当を追加'"));
    expect(source, contains('details.addAllowance'));
    expect(source, contains('details.removeAllowance'));
    expect(source, contains("'allowanceNames': allowanceNames"));
    expect(source, isNot(contains("suffixText: '円'")));
  });
}
