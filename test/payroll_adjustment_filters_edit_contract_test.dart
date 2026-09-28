import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll adjustment supports worker item and period filters', () {
    final page = read('lib/features/payroll/payroll_adjustment_page.dart');

    expect(page, contains('_workerFilter'));
    expect(page, contains('_typeFilter'));
    expect(page, contains('_startFilter'));
    expect(page, contains('_endFilter'));
    expect(page, contains('期間を指定'));
    expect(page, contains('すべての項目'));
  });

  test('existing payroll adjustment can be edited with audit history', () {
    final page = read('lib/features/payroll/payroll_adjustment_page.dart');
    final repository =
        read('lib/features/payroll/payroll_adjustment_repository.dart');
    final sql = read(
      'supabase/migrations/20260929213000_add_payroll_adjustment_edit_rpc.sql',
    );

    expect(page, contains('給与調整を修正'));
    expect(page, contains('修正を保存'));
    expect(repository, contains("'update_payroll_adjustment'"));
    expect(sql, contains("'adjustment_update'"));
    expect(sql, contains("'before'"));
    expect(sql, contains("'after'"));
    expect(sql, contains('cancelled payroll adjustment cannot be edited'));
  });
}
