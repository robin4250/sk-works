import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('personnel bundle contains basic profile, qualifications, and upstream docs', () {
    final sql = File(
      'supabase/migrations/20260930054500_add_personnel_bundle_company_exchange.sql',
    ).readAsStringSync();

    expect(sql, contains("'kind','worker_personnel'"));
    expect(sql, contains("'name',r.name"));
    expect(sql, contains("'kana',r.kana"));
    expect(sql, contains("'phone',r.phone"));
    expect(sql, contains("'email',r.email"));
    expect(sql, contains("'affiliation',r.affiliation"));
    expect(sql, contains("'role',r.role"));
    expect(sql, contains("'experience_years',r.experience_years"));
    expect(sql, contains('payload_kind'));
    expect(sql, contains("'qualification'"));
    expect(sql, contains("dr.scope='upstream'"));
    expect(sql, contains("'worker-documents'"));
  });

  test('personnel basic payload excludes worker notes and internal documents', () {
    final sql = File(
      'supabase/migrations/20260930054500_add_personnel_bundle_company_exchange.sql',
    ).readAsStringSync();

    final start = sql.indexOf("elsif x->>'kind'='worker_personnel' then");
    final end = sql.indexOf("for item in", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final basicBlock = sql.substring(start, end);
    expect(basicBlock, isNot(contains("'notes',r.notes")));
    expect(sql, isNot(contains("dr.scope='internal'")));
  });
}
