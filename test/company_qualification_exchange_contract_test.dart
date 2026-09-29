import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification company exchange stores structured payload and lineage', () {
    final sql = File(
      'supabase/migrations/20260930054000_add_structured_company_qualification_exchange.sql',
    ).readAsStringSync();

    expect(sql, contains('private.company_data_delivery_items'));
    expect(sql, contains("'kind','worker_qualification'"));
    expect(sql, contains("'qualification'"));
    expect(sql, contains("'certificate_number'"));
    expect(sql, contains("'qualification_name'"));
    expect(sql, contains("'worker_name'"));
    expect(sql, contains("x->>'kind'='received_data'"));
    expect(sql, contains('source_item_id'));
    expect(sql, contains("jsonb_build_array(cn)||r.company_path"));
  });

  test('qualification certificate attachment uses private certificate bucket', () {
    final sql = File(
      'supabase/migrations/20260930054000_add_structured_company_qualification_exchange.sql',
    ).readAsStringSync();

    expect(sql, contains("'qualification-certificates'"));
    expect(sql, contains('r.attachment_path is not null'));
  });
}
