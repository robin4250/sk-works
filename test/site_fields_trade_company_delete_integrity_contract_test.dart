import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('site detail and edit expose the same registered fields', () {
    final page = read('lib/features/sites/site_detail_page.dart');

    for (final label in [
      '現場名',
      '取引先',
      '状態',
      '現場正式名称',
      '担当者',
      '現場責任者',
      '責任者電話番号',
      '現場住所',
      '最寄りの駅',
      '開始日',
      '終了日',
      '備考',
    ]) {
      expect(page, contains(label));
    }

    expect(page, contains("'customer_id': _customerId!"));
    expect(page, contains("'manager_worker_id': _managerWorkerId ?? ''"));
    expect(page, contains("'starts_at': _startDate.text.trim()"));
    expect(page, contains("'ends_at': _endDate.text.trim()"));
    expect(page, isNot(contains("controller: _creator")));
  });

  test('site customer edit uses registered trade companies', () {
    final repository = read('lib/features/sites/site_cloud_repository.dart');
    final page = read('lib/features/sites/site_detail_page.dart');

    expect(repository, contains("loadCustomerTradeCompanies"));
    expect(repository, contains("'trade_company_workspace'"));
    expect(repository, contains("role != 'customer' && role != 'both'"));
    expect(page, contains('DropdownButtonFormField<String>('));
    expect(page, contains("_tr('取引先', 'Business Partner')"));
    expect(
      page,
      contains('登録済みの取引会社から取引先を選択してください'),
    );
  });

  test('site change approval accepts all unified persisted fields', () {
    final migration = read(
      'supabase/migrations/'
      '20261006133909_site_fields_and_trade_company_delete_integrity.sql',
    );

    for (final key in [
      "'name'",
      "'customer_id'",
      "'status'",
      "'formal_name'",
      "'manager_worker_id'",
      "'representative_name'",
      "'representative_phone'",
      "'address'",
      "'nearest_station'",
      "'starts_at'",
      "'ends_at'",
      "'notes'",
    ]) {
      expect(migration, contains(key));
    }

    expect(
      migration,
      contains("tc.trade_role in ('customer','both')"),
    );
    expect(migration, contains('customer_id=case when values_to_set?'));
    expect(
      migration,
      contains('manager_worker_id=case when values_to_set?'),
    );
  });

  test('trade company deletion blocks referenced business data', () {
    final repository =
        read('lib/features/companies/trade_company_repository.dart');
    final page = read('lib/features/companies/trade_company_page.dart');
    final migration = read(
      'supabase/migrations/'
      '20261006133909_site_fields_and_trade_company_delete_integrity.sql',
    );

    expect(repository, contains("'delete_trade_company_checked'"));
    expect(repository, contains("raw['deleted'] == true"));
    expect(page, contains('final stillExists = _items.any'));
    expect(migration, contains('この取引会社は現場で使用されているため削除できません'));
    expect(migration, contains('この取引会社は請求書で使用されているため削除できません'));
    expect(migration, contains('この協力会社は支払証明書で使用されているため削除できません'));
    expect(migration, contains('この協力会社は従業員情報で使用されているため削除できません'));
    expect(migration, contains('SKO連携中のため削除できません'));
  });
}
