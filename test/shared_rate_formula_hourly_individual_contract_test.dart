import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/rate_formula_settings.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('hourly and daily bases share the same multiplier system', () {
    const daily = RateFormulaSettings();
    const hourly = RateFormulaSettings(hourlyBase: true);

    expect(daily.overtime(16000), 2500);
    expect(hourly.overtime(2000), 2500);
    expect(daily.early(16000), 2500);
    expect(hourly.early(2000), 2500);
    expect(daily.night(16000), 24000);
    expect(hourly.night(2000), 24000);
    expect(daily.holiday(16000), 21600);
    expect(hourly.holiday(2000), 21600);
    expect(daily.holidayNight(16000), 25600);
    expect(hourly.holidayNight(2000), 25600);
  });

  test('formula metadata persists base mode hourly amount and editable factors', () {
    const formula = RateFormulaSettings(hourlyBase: true);
    final map = formula.toMap(hourlyRateYen: 2000);

    expect(map['base_mode'], 'hourly');
    expect(map['hourly_rate_yen'], 2000);
    expect(map['hours_per_day'], 8);
    expect(map['overtime_multiplier'], 1.25);
    expect(map['night_multiplier'], 1.5);
    expect(map['holiday_multiplier'], 1.35);
    expect(map['holiday_night_multiplier'], 1.6);
  });

  test('individual payroll uses formula editor and stores derived rates', () {
    final page =
        read('lib/features/payroll/individual_payroll_settings_page.dart');
    final widget = read('lib/widgets/rate_formula_editor_card.dart');

    expect(page, contains('RateFormulaEditorCard'));
    expect(page, contains("values['rate_formula']"));
    expect(page, contains("values['rate_overrides']"));
    expect(page, contains("values['hourly_rate_yen']"));
    expect(widget, contains("label: Text('日給')"));
    expect(widget, contains("label: Text('時給')"));
    expect(widget, contains('計算式を変更'));
    expect(widget, contains('直接入力'));
  });

  test('invoice and payment settings persist the shared formula contract', () {
    final invoiceSql = read(
      'supabase/migrations/'
      '20261006173142_common_rate_formula_invoice_hourly.sql',
    );
    final paymentSql = read(
      'supabase/migrations/'
      '20261006171219_payment_certificate_formula_allowance_welfare_tax.sql',
    );

    expect(invoiceSql, contains('resolve_rate_formula'));
    expect(invoiceSql, contains("'base_mode'"));
    expect(invoiceSql, contains("'hourly_rate_yen'"));
    expect(invoiceSql, contains('rate_formula_label'));
    expect(paymentSql, contains('rate_formula'));
    expect(paymentSql, contains('allowances'));
    expect(paymentSql, contains('welfare_rate'));
    expect(paymentSql, contains('tax_rate'));
  });
}
