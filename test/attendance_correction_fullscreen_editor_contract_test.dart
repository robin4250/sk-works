import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance correction uses full screen editor instead of dialog', () {
    final source = File('lib/features/attendance/bulk_attendance_correction_page.dart').readAsStringSync();
    expect(source, contains('_AttendanceCorrectionEditPage'));
    expect(source, contains("title: const Text('勤務修正入力'"));
    expect(source, contains('keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag'));
    expect(source, contains('MediaQuery.viewInsetsOf(context).bottom'));
    expect(source, contains("label: const Text('修正内容を保存')"));
  });
}
