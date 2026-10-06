import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin site invoice settings support exactly one billing method', () {
    final page = File(
      'lib/features/sites/admin_site_financial_page.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/features/sites/admin_site_financial_repository.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20261003134047_add_site_invoice_billing_methods.sql',
    ).readAsStringSync();

    expect(page, contains("'1日単価'"));
    expect(page, contains("'月単価'"));
    expect(page, contains("'平米単価'"));
    expect(page, contains("'平米数'"));
    expect(page, contains("'請負金額'"));
    expect(page, contains("'平米単価と平米数は両方入力してください'"));
    expect(page, contains("'請求方式は1日単価・月単価・平米・請負のどれか1つにしてください'"));
    expect(page, contains("'夜勤'"));
    expect(page, contains("'請求書用 手当'"));

    expect(repo, contains('billingSquareMeterUnitPriceYen'));
    expect(repo, contains('billingSquareMeterQuantity'));
    expect(repo, contains('billingContractAmountYen'));
    expect(repo, contains("return '1日単価';"));
    expect(repo, contains("return '月単価';"));
    expect(repo, contains("return '平米';"));
    expect(repo, contains("return '請負';"));
    expect(repo, contains("return '未設定';"));
    expect(repo, contains('nightHourRateYen'));
    expect(repo, contains('billingMonthlyRateYen'));
    expect(repo, contains('billingAllowance1Name'));

    expect(migration, contains('billing_square_meter_unit_price_yen integer not null default 0'));
    expect(migration, contains('billing_square_meter_quantity numeric(12,3) not null default 0'));
    expect(migration, contains('billing_contract_amount_yen integer not null default 0'));
    expect(migration, contains('site_financial_settings_billing_square_pair_check'));
    expect(migration, contains('site_financial_settings_single_billing_method_check'));
  });
}
