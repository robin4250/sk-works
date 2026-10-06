import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('allowance unit editor sits beside allowance name and amount', () {
    final page =
        read('lib/features/settings/company_rate_settings_page.dart');

    expect(page, contains("labelText: '手当\$number 名称'"));
    expect(page, contains("labelText: '手当\$number 単位'"));
    expect(page, contains("hintText: '回・日・時間・件など'"));
    expect(page, contains('週間表示・カレンダー表示・月集計に反映'));
  });

  test('attendance week month and pdf use saved allowance units', () {
    final sheet =
        read('lib/features/attendance/worker_attendance_sheet_page.dart');
    final repo =
        read('lib/features/attendance/worker_attendance_sheet_repository.dart');
    final pdf =
        read('lib/features/attendance/attendance_pdf_service.dart');

    expect(repo, contains("'my_attendance_allowance_units'"));
    expect(sheet, contains("day.allowanceUnits[name] ?? '回'"));
    expect(sheet, contains("data.allowanceUnits[entry.key] ?? '回'"));
    expect(pdf, contains("data.allowanceUnits[entry.key] ?? '回'"));
  });
}
