import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('allowance unit editor saves custom units with legacy default', () {
    final page =
        read('lib/features/settings/company_rate_settings_page.dart');
    final repository =
        read('lib/features/settings/company_rate_settings_repository.dart');

    expect(page, contains("labelText: '単位（回・日・個など）'"));
    expect(page, contains("hintText: '例：回 / 日 / 個 / 式'"));
    expect(repository, contains("'p_allowance_1_unit'"));
    expect(repository, contains("'p_allowance_2_unit'"));
    expect(repository, contains("'p_allowance_3_unit'"));
    expect(repository, contains("? '回'"));
  });

  test('weekly calendar and monthly allowance summary use saved units', () {
    final page =
        read('lib/features/attendance/worker_attendance_sheet_page.dart');
    final repository =
        read('lib/features/attendance/worker_attendance_sheet_repository.dart');

    expect(page, contains("day.allowanceUnits[name] ?? '回'"));
    expect(
      page,
      contains("data.allowanceUnits[entry.key] ?? '回'"),
    );
    expect(repository, contains("'my_attendance_allowance_units'"));
  });
}
