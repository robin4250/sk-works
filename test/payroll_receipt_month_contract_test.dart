import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/payroll_unit_conditions_repository.dart';

Map<String, dynamic> publication() => {
  'id': 'publication-item', 'name': '登録手当', 'section': 'earning',
  'unit': 'day', 'rate_yen': 2000, 'quantity': 0, 'amount_yen': 0,
  'quantity_month': '2026-10-01',
};
Map<String, dynamic> receipt() => {
  'id': 'receipt-item', 'name': '確定手当', 'section': 'earning',
  'unit': 'day', 'rate_yen': 2000, 'quantity': 2, 'amount_yen': 4000,
  'origin': 'company_common', 'source': 'confirmed_checkout_receipt',
  'registration_version': 3, 'work_dates': ['2026-10-02', '2026-10-03'],
};
Map<String, dynamic> response(List<Map<String, dynamic>> items,
    {String month = '2026-10-01'}) => {
  'version': 2, 'month': month, 'can_edit': true, 'items': <dynamic>[],
  'company_common': {
    'contract_version': 1, 'items': items, 'history_missing': false,
    'frozen': false, 'source': {'publication_version': 4, 'items': items},
    'resolution': {'blocked': false, 'reasons': <dynamic>[]},
  },
};

void main() {
  test('mixed publication and confirmed receipt preserve amounts and raw CAS source', () {
    final raw = response([publication(), receipt()]);
    final before = jsonEncode(raw);
    final value = PayrollUnitConditions.fromJson(jsonDecode(before));
    expect(value.companyCommonItems.length, 2);
    expect(value.companyCommonItems.last['amount_yen'], 4000);
    expect(value.companyCommonItems.last['quantity'], 2);
    expect(value.companyCommonItems.last.containsKey('quantity_month'), false);
    expect(value.companyCommonSourceJson,
        jsonEncode((raw['company_common'] as Map)['source']));
    expect(jsonEncode(raw), before);
  });
  test('normal employee publication-only response remains identical', () {
    final value = PayrollUnitConditions.fromJson(response([publication()]));
    expect(value.companyCommonItems.single, publication());
  });
  final invalid = <String, Map<String, dynamic>>{
    'different month': {'work_dates': ['2026-09-30']},
    'mixed months': {'work_dates': ['2026-10-01', '2026-11-01']},
    'empty dates': {'work_dates': <dynamic>[]},
    'missing dates': {'work_dates': null},
    'non-list dates': {'work_dates': '2026-10-02'},
    'non-string date': {'work_dates': [20261002]},
    'duplicate date': {'work_dates': ['2026-10-02', '2026-10-02']},
    'overflow day': {'work_dates': ['2026-10-32']},
    'timestamp': {'work_dates': ['2026-10-02T00:00:00Z']},
    'noncanonical date': {'work_dates': ['2026-10-2']},
    'wrong origin': {'origin': 'individual'},
    'wrong source': {'source': 'manual_hours'},
    'unsupported monthly receipt': {'unit': 'month'},
    'missing registration version': {'registration_version': null},
    'zero registration version': {'registration_version': 0},
    'noninteger registration version': {'registration_version': 3.5},
    'explicit wrong month': {'quantity_month': '2026-09-01'},
    'explicit null month': {'quantity_month': null},
    'negative amount': {'amount_yen': -1},
    'negative rate': {'rate_yen': -1},
    'negative quantity': {'quantity': -1},
  };
  for (final entry in invalid.entries) {
    test('receipt compatibility rejects ${entry.key}', () {
      expect(() => PayrollUnitConditions.fromJson(response([
        {...receipt(), ...entry.value},
      ])), throwsStateError);
    });
  }
  test('missing month is not accepted for ordinary publication', () {
    final row = publication()..remove('quantity_month');
    expect(() => PayrollUnitConditions.fromJson(response([row])), throwsStateError);
  });
  test('existing duplicate-id rejection is retained', () {
    expect(() => PayrollUnitConditions.fromJson(response([receipt(), receipt()])),
        throwsStateError);
  });
  test('calendar boundary uses requested month, including leap year', () {
    for (final entry in {
      '2024-02-01': '2024-02-29', '2026-01-01': '2026-01-01',
      '2026-12-01': '2026-12-31',
    }.entries) {
      final row = {...receipt(), 'work_dates': [entry.value]};
      expect(PayrollUnitConditions.fromJson(response([row], month: entry.key))
          .companyCommonItems.single, row);
    }
    expect(() => PayrollUnitConditions.fromJson(response([
      {...receipt(), 'work_dates': ['2026-02-29']},
    ], month: '2026-02-01')), throwsStateError);
  });
  test('actual SDK reads exact worker/company/month with legacy receipt shape', () async {
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/rest/v1/rpc/payroll_unit_conditions');
      requests.add(Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response([publication(), receipt()])));
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    try {
      final repo = PayrollUnitConditionsRepository.forTesting(client, () => 'actor');
      final result = await repo.load('company-a', 'worker-target', '2026-10-01');
      expect(result.companyCommonItems.length, 2);
      expect(requests, [{'p_company_id': 'company-a',
        'p_worker_id': 'worker-target', 'p_month': '2026-10-01'}]);
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}
