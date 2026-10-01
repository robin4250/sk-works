import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company exchange restore uses one connected-company send flow', () {
    final common = File(
      'lib/features/people/company_transfer_send_page.dart',
    ).readAsStringSync();
    final repo = File(
      'lib/features/people/company_document_exchange_repository.dart',
    ).readAsStringSync();
    final inbox = File(
      'lib/features/people/company_delivery_inbox_page.dart',
    ).readAsStringSync();

    expect(common, contains("'接続済み会社'"));
    expect(common, contains("'全部送る'"));
    expect(common, contains("'選んで送る'"));
    expect(common, contains("'案内・備考メモ'"));
    expect(common, contains("'選択済み対象'"));
    expect(common, contains("'確定して送信'"));
    expect(common, contains("sendConnected("));
    expect(repo, contains("rpc('company_connection_targets')"));
    expect(repo, contains("'connected_parent_receive_code'"));

    for (final path in [
      'lib/features/people/personnel_bundle_send_page.dart',
      'lib/features/people/worker_document_send_page.dart',
      'lib/features/qualifications/qualification_send_page.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('CompanyTransferSendPage('),
      );
    }

    expect(inbox, contains("'協力会社'"));
    expect(inbox, contains("'接続済み親会社'"));
    expect(inbox, isNot(contains("'上位会社の受取コード'")));
    expect(inbox, contains("'保存しますか'"));
    expect(inbox, contains("'保存したデータを開く'"));
    expect(inbox, contains("'会社単位で一括保存'"));
    expect(inbox, contains("saveDeliveryItems("));
  });

  test('received delivery save state is server-side and authorized', () {
    final sql = File(
      'supabase/migrations/20261001214500_add_company_delivery_save_state.sql',
    ).readAsStringSync();

    expect(sql, contains('private.company_delivery_saved_items'));
    expect(sql, contains('recipient_company_id=c'));
    expect(sql, contains('auth.uid()'));
    expect(sql, contains('grant execute'));
  });
}
