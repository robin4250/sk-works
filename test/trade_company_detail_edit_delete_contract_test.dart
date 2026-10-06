import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('trade and subcontractor company rows open readable detail actions', () {
    final page = read('lib/features/companies/trade_company_page.dart');

    expect(page, contains("_detailLine('住所', item.address)"));
    expect(page, contains("_detailLine('電話番号', item.phone)"));
    expect(page, contains("_detailLine('法人番号', item.corporateNumber)"));
    expect(page, contains("label: const Text('会社情報を編集')"));
    expect(page, contains("label: const Text('契約設定')"));
    expect(page, contains("label: const Text('削除')"));
  });

  test('company edit preserves role and saves all registered fields', () {
    final page = read('lib/features/companies/trade_company_page.dart');

    expect(page, contains('tradeRole: item.tradeRole'));
    expect(page, contains('initial: item'));
    expect(page, contains('notes: draft.notes'));
    expect(page, contains("widget.initial == null ? '登録' : '保存'"));
  });

  test('company delete uses authenticated guarded rpc', () {
    final repository =
        read('lib/features/companies/trade_company_repository.dart');
    final migration = read(
      'supabase/migrations/20261006122723_add_trade_company_delete_rpc.sql',
    );

    expect(repository, contains("'delete_trade_company'"));
    expect(migration, contains('private.current_company_admin_id()'));
    expect(migration, contains('delete from public.trade_companies'));
    expect(migration, contains('revoke all on function public.delete_trade_company(uuid)'));
    expect(migration, contains('grant execute on function public.delete_trade_company(uuid)'));
  });
}
