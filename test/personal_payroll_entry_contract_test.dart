import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personal payroll statement entry is available to every signed-in role', () {
    final app = File('lib/app_v2.dart').readAsStringSync();
    final page =
        File('lib/features/payroll/payroll_statements_page.dart').readAsStringSync();

    expect(app, contains("key: 'payroll'"));
    expect(app, contains("label: SkoLanguageController.tr('給与明細')"));
    expect(app, contains("accessLabel: SkoLanguageController.tr('本人')"));
    expect(app, isNot(contains("if (!_isAdmin)\n        _MenuAction(\n          key: 'payroll'")));
    expect(app, contains("title: '給与明細'"));
    expect(app, contains('PayrollStatementsPage()'));
    expect(page, contains('loadMyStatements()'));
    expect(page, contains('PayrollStatementPreviewPage'));
  });

  test('management payroll review remains separate from personal payroll', () {
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(app, contains("key: 'payroll_review'"));
    expect(app, contains("label: SkoLanguageController.tr('給料一覧')"));
    expect(app, contains("title: '給料一覧'"));
    expect(app, contains('PayrollReviewPage()'));
  });
}
