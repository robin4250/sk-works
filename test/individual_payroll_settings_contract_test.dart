import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('individual payroll settings uses production payroll contract', () {
    final repository = File(
      'lib/features/payroll/individual_payroll_settings_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/payroll/individual_payroll_settings_page.dart',
    ).readAsStringSync();

    expect(repository, contains("rpc('payroll_workspace')"));
    expect(repository, contains("from('worker_payroll_settings')"));
    expect(repository, contains("onConflict: 'worker_id'"));
    expect(page, contains("'個別給与設定'"));
    expect(page, contains("'日勤・残業'"));
    expect(page, contains("'夜勤・早出'"));
    expect(page, contains("'休日夜勤・残業'"));
    expect(page, contains("'社会保険・月額'"));
    expect(page, contains('最終更新日：'));
    expect(page, contains("'個別給与設定を保存しますか？'"));
    expect(page, contains("'確定して保存'"));
  });
}
