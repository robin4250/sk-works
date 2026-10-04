import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trade and subcontractor pages share one company master', () {
    final page =
        File('lib/features/companies/trade_company_page.dart').readAsStringSync();
    final repo = File(
      'lib/features/companies/trade_company_repository.dart',
    ).readAsStringSync();
    final app = File('lib/app_v2.dart').readAsStringSync();

    expect(page, contains('TradeCompanyPageMode.customer'));
    expect(repo, contains('TradeCompanyPageMode { customer, subcontractor }'));
    expect(page, contains('SKO連携なしでも登録できます'));
    expect(repo, contains("rpc('trade_company_workspace')"));
    expect(repo, contains("rpc('sync_trade_company_directory')"));
    expect(app, contains("key: 'trade_companies'"));
    expect(app, contains("key: 'subcontractors'"));
  });

  test('company contract supports all requested calculation methods', () {
    final page =
        File('lib/features/companies/trade_company_page.dart').readAsStringSync();
    final repo = File(
      'lib/features/companies/trade_company_repository.dart',
    ).readAsStringSync();

    for (final value in [
      '1日単価',
      '月単価',
      '平米単価',
      '平米数',
      '請負',
    ]) {
      expect(page, contains(value));
    }
    expect(repo, contains('dailyRateYen'));
    expect(repo, contains('monthlyRateYen'));
    expect(repo, contains('squareMeterUnitPriceYen'));
    expect(repo, contains('squareMeterQuantity'));
    expect(repo, contains('contractAmountYen'));
  });

  test('link merge and site calculation conflict always require confirmation', () {
    final page =
        File('lib/features/companies/trade_company_page.dart').readAsStringSync();
    final repo = File(
      'lib/features/companies/trade_company_repository.dart',
    ).readAsStringSync();

    expect(page, contains('SKO連携候補が見つかりました'));
    expect(page, contains('会社データを統合しますか？'));
    expect(page, contains('同じ会社であることを確認してから統合してください。'));
    expect(page, contains('barrierDismissible: false'));
    expect(page, contains('管理現場の設定を使う'));
    expect(page, contains('取引会社の契約を使う'));
    expect(page, contains('下請け会社の契約を使う'));
    expect(repo, contains("rpc('trade_company_link_candidates'"));
    expect(repo, contains("rpc('select_site_calculation_source'"));
  });

  test('production trade company migrations are mirrored in repository', () {
    for (final path in [
      'supabase/migrations/20261004132001_add_trade_company_master_and_contract_sources.sql',
      'supabase/migrations/20261004132037_restrict_trade_company_master_to_rpc.sql',
      'supabase/migrations/20261004132201_add_trade_company_calculation_conflicts.sql',
      'supabase/migrations/20261004134247_sync_trade_company_directory_sources.sql',
      'supabase/migrations/20261004140858_apply_trade_company_calculation_source.sql',
      'supabase/migrations/20261004141035_refresh_outputs_after_trade_contract_change.sql',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });
}
