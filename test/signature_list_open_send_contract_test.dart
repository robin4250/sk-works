import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signature list uses dedicated source RPC', () {
    final list = File('lib/features/people/signature_list_page.dart').readAsStringSync();
    final repo = File('lib/features/people/company_document_exchange_repository.dart').readAsStringSync();
    final send = File('lib/features/people/company_transfer_send_page.dart').readAsStringSync();
    expect(list, contains('listSignatureSources'));
    expect(repo, contains("rpc('company_signature_sources')"));
    expect(send, contains("widget.sourceKind == 'daily_report_signature'"));
  });

  test('signature exchange allows management including subadmin', () {
    final sql = File(
      'supabase/migrations/20261004084309_allow_subadmin_signature_exchange.sql',
    ).readAsStringSync();
    expect(sql, contains("in ('owner','admin','manager')"));
    expect(sql, contains('company_signature_sources'));
    expect(sql, contains('company_connection_targets'));
    expect(sql, contains('send_connected_signature_data'));
  });
}
