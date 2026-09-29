import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company document exchange includes only upstream worker documents', () {
    final sql = File(
      'supabase/migrations/20260930053500_extend_company_document_exchange_worker_docs.sql',
    ).readAsStringSync();

    expect(sql, contains("'kind','worker_document'"));
    expect(sql, contains("'worker-documents'::text bucket"));
    expect(sql, contains("dr.scope='upstream'"));
    expect(sql, contains("s.status in ('submitted','verified')"));
    expect(sql, contains("w.company_id=c"));
    expect(sql, contains("dr.company_id=c"));
  });

  test('existing received-item forwarding path remains intact', () {
    final sql = File(
      'supabase/migrations/20260930053500_extend_company_document_exchange_worker_docs.sql',
    ).readAsStringSync();

    expect(sql, contains("if x->>'kind'='received' then"));
    expect(sql, contains('source_item_id'));
    expect(sql, contains("ancestry:=jsonb_build_array(cn)||r.company_path"));
  });
}
