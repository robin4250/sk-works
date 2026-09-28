import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('past attendance correction supports multi-select and one final signature', () {
    final page =
        read('lib/features/attendance/bulk_attendance_correction_page.dart');

    expect(page, contains('過去分まとめて修正'));
    expect(page, contains('_selectedIds'));
    expect(page, contains('CheckboxListTile'));
    expect(page, contains('最後に1回だけおまとめサイン'));
    expect(page, contains('SignatureCapturePage'));
    expect(page, contains('repository.createDraft'));
    expect(page, contains('repository.submit'));
  });

  test('past correction keeps before and after values before submission', () {
    final repository =
        read('lib/features/attendance/attendance_correction_repository.dart');

    expect(repository, contains('original_snapshot'));
    expect(repository, contains('proposed_snapshot'));
    expect(repository, contains('change_summary'));
    expect(repository, contains('attendance_correction_requests'));
    expect(repository, contains('attendance_correction_items'));
  });

  test('attendance page exposes past bulk correction only to attendance managers', () {
    final page = read('lib/features/attendance/attendance_cloud_page.dart');

    expect(page, contains('過去分まとめて修正'));
    expect(page, contains('_canManageAttendanceEntries'));
    expect(page, contains('_openBulkCorrection'));
  });
}
