import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('payroll settings seed optional earnings deductions and payment day', () {
    final page =
        read('lib/features/payroll/individual_payroll_settings_page.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006162510_payroll_flexible_earnings_deductions_payment_day.sql',
    );

    for (final label in [
      '勤続手当',
      '役職手当',
      '家族手当',
      '働き方手当',
      '介護保険料',
      '厚生年金保険',
      '雇用保険料',
      'SKO会費',
    ]) {
      expect(page, contains(label));
      expect(migration, contains(label));
    }

    expect(page, contains("'payment_day'"));
    expect(page, contains("label: const Text('支給項目を追加')"));
    expect(page, contains("label: const Text('控除項目を追加')"));
    expect(migration, contains('payment_day integer not null default 25'));
    expect(migration, contains("'支払日',payment_day"));
  });

  test('payroll PDF grows rows for every registered earning and deduction', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');

    expect(pdf, contains('const columns = 5'));
    expect(pdf, contains('for (var index = 0; index < visible.length; index += columns)'));
    expect(pdf, contains('registeredLabels.contains(entry.key)'));
    expect(pdf, contains('groups.length > 2'));
    expect(pdf, contains('_balancedMoneySection'));
    expect(pdf, contains("'custom_earnings'"));
    expect(pdf, contains("'custom_deductions'"));
  });

  test('legacy aggregate other earning and deduction labels are not rendered', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');
    final page =
        read('lib/features/payroll/individual_payroll_settings_page.dart');

    expect(pdf, contains("'その他支給'"));
    expect(pdf, contains("'その他の支給'"));
    expect(pdf, contains("'その他控除'"));
    expect(pdf, contains("'その他の控除'"));
    expect(pdf, contains('_isAggregatePlaceholder'));
    expect(page, isNot(contains("'other_deduction_monthly', 'その他控除・月額'")));
    expect(page, isNot(contains("_amountField(\n                          'other_deduction_monthly'")));
  });

  test('payroll header uses configured payment day for next-month date', () {
    final pdf = read('lib/features/payroll/payroll_pdf_service.dart');

    expect(pdf, contains('_paymentDate(statement, detail)'));
    expect(pdf, contains("detail['支払日']"));
    expect(pdf, contains('statement.periodEnd.month + 1'));
    expect(pdf, contains('day > lastDay ? lastDay : day'));
  });
}
