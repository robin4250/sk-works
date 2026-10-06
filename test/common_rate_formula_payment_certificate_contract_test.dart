import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/rate_formula_settings.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('shared rate formulas use requested defaults', () {
    const formula = RateFormulaSettings();
    expect(formula.overtime(16000), 2500);
    expect(formula.early(16000), 2500);
    expect(formula.night(16000), 24000);
    expect(formula.holiday(16000), 21600);
    expect(formula.holidayNight(16000), 25600);
    expect(formula.nightOvertime(16000), 3750);
    expect(formula.holidayOvertime(16000), 3375);
    expect(formula.holidayNightOvertime(16000), 4000);
  });

  test('hourly base uses the same multipliers without dividing by daily hours', () {
    const formula = RateFormulaSettings();
    expect(formula.overtime(2000, hourlyBase: true), 2500);
    expect(formula.early(2000, hourlyBase: true), 2500);
    expect(formula.night(2000, hourlyBase: true), 24000);
    expect(formula.holiday(2000, hourlyBase: true), 21600);
    expect(formula.holidayNight(2000, hourlyBase: true), 25600);
    expect(formula.nightOvertime(2000, hourlyBase: true), 3750);
    expect(formula.holidayOvertime(2000, hourlyBase: true), 3375);
    expect(formula.holidayNightOvertime(2000, hourlyBase: true), 4000);
    expect(
      formula.overtimeFormula(2000, hourlyBase: true),
      '2000 × 1.25',
    );
    expect(
      formula.nightFormula(2000, hourlyBase: true),
      '2000 × 8 × 1.5',
    );
  });

  test('payment certificate settings show formulas, direct override and extras', () {
    final page = read('lib/features/payroll/payment_certificates_page.dart');
    final repo = read('lib/features/payroll/payment_certificate_repository.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006171219_payment_certificate_formula_allowance_welfare_tax.sql',
    );

    for (final label in [
      '残業 1時間単価',
      '早出 1時間単価',
      '夜勤 1日単価',
      '夜勤残業 1時間単価',
      '休日出勤 1日単価',
      '休日残業 1時間単価',
      '休日夜勤 1日単価',
      '休日夜勤残業 1時間単価',
    ]) {
      expect(page, contains(label));
    }

    expect(page, contains('自動計算'));
    expect(page, contains('式:'));
    expect(page, contains('0なら自動計算'));
    expect(page, contains('手当を追加'));
    expect(page, contains('福利厚生費率'));
    expect(page, contains('消費税率'));
    expect(repo, contains('RateFormulaSettings'));
    expect(repo, contains('p_rate_formula'));
    expect(repo, contains('p_allowances'));
    expect(repo, contains('value.overtimeRate'));
    expect(repo, contains('value.holidayNightOvertimeRate'));
    expect(repo, contains("workContent: '（福利厚生費）'"));
    expect(repo, contains("workContent: '（消費税）'"));
    expect(repo, contains('final gross = preTax + tax'));
    expect(migration, contains('holiday_night_overtime_multiplier'));
    expect(migration, contains("'福利厚生費'"));
    expect(migration, contains("'消費税'"));
  });
}
