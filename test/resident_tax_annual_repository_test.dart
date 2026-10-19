import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/resident_tax_annual_repository.dart';

const company = '10000000-0000-0000-0000-000000000001';
const worker = '40000000-0000-0000-0000-000000000001';
const requestId = '80000000-0000-0000-0000-000000000001';
Map<String, dynamic> annualResponse() => {
  'company_id': company, 'fiscal_year': 2030, 'previous_fiscal_year': 2029, 'current_fiscal_year': 2030,
  'can_edit': true, 'scope_complete': true, 'complete': false, 'receipt': null,
  'snapshot': {'cohort_hash': 'fixture', 'workers': [{'worker_id': worker, 'source': {'state': null, 'legacy_amount_yen': 5000}}]},
  'workers': [{'worker_id': worker, 'name': '確認用社員', 'current_amount_yen': 5000,
    'amounts': List.filled(12, 5000), 'previous_amounts': List.filled(12, null),
    'current_amounts': List.filled(12, 5000), 'confirmed': false, 'excluded': false,
    'reason': null, 'source': {'state': null, 'legacy_amount_yen': 5000},
    'confirmed_at': null, 'last_updated_at': null, 'undo_request_id': requestId,
    'undo_before_amounts': List.filled(12, 4000)}],
};

void main() {
  test('company/year, twelve real amounts and prior-year unknown data are validated', () {
    final row = annualResponse();
    final data = ResidentTaxAnnualData.fromJson(row, company, 2030);
    expect(data.workers.single.previousAmounts, List.filled(12, null));
    expect(() => ResidentTaxAnnualData.fromJson(row, 'other-company', 2030), throwsStateError);
    expect(() => ResidentTaxAnnualData.fromJson(row, company, 2031), throwsStateError);
    (row['workers'] as List).single['current_amounts'] = [5000];
    expect(() => ResidentTaxAnnualData.fromJson(row, company, 2030), throwsFormatException);
  });
  for (final mode in ['valid', 'same_token_aba', 'conflict', 'wrong_receipt']) {
    test('real SDK annual read/subset save uses pinned actor and exact snapshot: $mode', () async {
      const uid = '00000000-0000-0000-0000-000000000001';
      final user = {'id': uid, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'fixture@example.invalid',
        'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}};
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      final calls = <Map<String, dynamic>>[];
      late SupabaseClient client;
      client = SupabaseClient('https://fixture.invalid', 'fixture-public', authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((req) async {
          Object? body;
          if (req.url.path == '/auth/v1/token') {
            body = {'access_token': token, 'refresh_token': 'fixture', 'token_type': 'bearer', 'expires_in': 3600, 'user': user};
          } else if (req.url.path == '/auth/v1/logout') { return http.Response('', 204, request: req); }
          else if (req.url.path == '/rest/v1/rpc/read_company_resident_tax_annual') {
            expect(req.headers['Authorization'], 'Bearer $token'); body = annualResponse();
          } else if (req.url.path == '/rest/v1/rpc/save_company_resident_tax_annual') {
            expect(req.headers['Authorization'], 'Bearer $token'); calls.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
            if (mode == 'same_token_aba') {
              await client.auth.signOut(scope: SignOutScope.local);
              await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
            }
            if (mode == 'conflict') return http.Response(jsonEncode({'code': '40001', 'message': 'source conflict'}), 409,
              headers: {'content-type': 'application/json'}, request: req);
            body = {'request_id': mode == 'wrong_receipt' ? 'other' : requestId,
              'company_id': company, 'fiscal_year': 2030, 'snapshot': annualResponse()['snapshot']};
          } else { throw StateError('unexpected request'); }
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}, request: req);
        }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture');
      final repo = SupabaseResidentTaxAnnualRepository(client: client);
      final current = await repo.read(company, 2030);
      final result = repo.save(current, [ResidentTaxAnnualInput(workerId: worker, amounts: List.filled(12, 0), excluded: false)], requestId);
      if (mode == 'valid') { await result; }
      else if (mode == 'conflict') { await expectLater(result, throwsA(isA<ResidentTaxAnnualReloadRequired>())); }
      else { await expectLater(result, throwsStateError); }
      expect(calls.single['p_expected_snapshot'], annualResponse()['snapshot']);
      expect((calls.single['p_entries'] as List).single, {'worker_id': worker, 'amounts': List.filled(12, 0),
        'confirmed': true, 'excluded': false, 'reason': null});
    });
  }
}
