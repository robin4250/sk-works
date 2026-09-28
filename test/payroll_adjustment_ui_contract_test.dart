import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll adjustment page stays behind secondary authentication', () {
    final app = read('lib/app_v2.dart');

    expect(app, contains("'payroll_adjustments': 'can_view_payroll_adjustments'"));
    expect(app, contains("key: 'payroll_adjustments'"));
    expect(app, contains('SecondaryProtectedPage('));
    expect(app, contains('child: const PayrollAdjustmentPage()'));
  });

  test('payroll adjustment page supports company labels and controlled writes', () {
    final page = read('lib/features/payroll/payroll_adjustment_page.dart');
    final repository =
        read('lib/features/payroll/payroll_adjustment_repository.dart');

    expect(page, contains('ページ名を変更'));
    expect(page, contains('項目追加'));
    expect(page, contains('取消する'));
    expect(page, contains('canManage'));
    expect(page, contains('canRename'));

    expect(repository, contains("rpc('payroll_adjustment_access')"));
    expect(repository, contains("rpc('create_payroll_adjustment'"));
    expect(repository, contains("rpc('cancel_payroll_adjustment'"));
    expect(repository, contains("rpc('upsert_payroll_adjustment_type'"));
  });

  test('menu label is refreshed after admin renames payroll adjustment page', () {
    final app = read('lib/app_v2.dart');

    expect(app, contains('_payrollAdjustmentLabel'));
    expect(app, contains('_loadPayrollAdjustmentAccess()'));
    expect(app, contains("if (key == 'payroll_adjustments')"));
  });
}
