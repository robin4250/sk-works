import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('individual payroll settings use shared editable rate formulas', () {
    final page =
        read('lib/features/payroll/individual_payroll_settings_page.dart');
    final formula = read('lib/domain/rate_formula_settings.dart');

    expect(page, contains("import '../../domain/rate_formula_settings.dart'"));
    expect(page, contains("values['rate_formula'] = formula.toMap()"));
    expect(page, contains("values['rate_overrides'] = rateOverrides"));
    expect(page, contains('0なら自動計算 / 現在'));
    expect(page, contains('計算式:'));
    expect(page, contains('夜勤残業'));
    expect(page, contains('休日残業'));
    expect(page, contains('休日夜勤残業'));

    expect(formula, contains('this.overtimeMultiplier = 1.25'));
    expect(formula, contains('this.earlyMultiplier = 1.25'));
    expect(formula, contains('this.nightMultiplier = 1.5'));
    expect(formula, contains('this.nightOvertimeMultiplier = 1.5'));
    expect(formula, contains('this.holidayMultiplier = 1.35'));
    expect(formula, contains('this.holidayOvertimeMultiplier = 1.35'));
    expect(formula, contains('this.holidayNightMultiplier = 1.6'));
    expect(formula, contains('this.holidayNightOvertimeMultiplier = 1.6'));
  });

  test('shared formulas support daily base and direct override mode', () {
    final formula = read('lib/domain/rate_formula_settings.dart');

    expect(formula, contains("'base_mode': hourlyBase ? 'hourly' : 'daily'"));
    expect(formula, contains('effectiveRate(int direct, int calculated)'));
    expect(formula, contains('direct > 0 ? direct : calculated'));
  });
}
