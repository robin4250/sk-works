import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/company_rate_settings_repository.dart';

const company = '10000000-0000-0000-0000-000000000001';
const actor = '20000000-0000-0000-0000-000000000001';
Map<String, dynamic> values() => {
  'tax_rate': 10, 'welfare_rate': 15,
  'overtime_hour_rate_yen': 1000, 'early_hour_rate_yen': 1100,
  'night_hour_rate_yen': 1200, 'holiday_day_rate_yen': 1300,
};

void main() {
  for (final mode in ['saved', 'missing_rpc', 'wrong_company', 'wrong_result', 'invalid_money', 'actor_changed']) {
    test('partial company defaults RPC preserves allowance ownership: $mode', () async {
      final user = {'id': actor, 'aud': 'authenticated', 'email': 'fixture@example.invalid',
        'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}};
      String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${part({'alg': 'HS256'})}.${part({'sub': actor,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      final calls = <String>[];
      Map<String, dynamic>? sent;
      late SupabaseClient client;
      client = SupabaseClient('https://fixture.invalid', 'fixture-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((req) async {
          Object body;
          if (req.url.path == '/auth/v1/token') {
            body = {'access_token': token, 'refresh_token': 'fixture', 'token_type': 'bearer',
              'expires_in': 3600, 'user': user};
          } else if (req.url.path == '/auth/v1/logout') {
            return http.Response('', 204, request: req);
          } else {
            expect(req.headers['Authorization'], 'Bearer $token');
            calls.add(req.url.path);
            if (mode == 'missing_rpc') {
              return http.Response(jsonEncode({'code':'PGRST202','message':'unavailable'}), 404,
                headers:{'content-type':'application/json'}, request:req);
            }
            body = {'contract_version':1,'company_id':company,...values()};
            if (req.url.path.endsWith('save_company_rate_defaults')) {
              sent = Map<String,dynamic>.from(jsonDecode(req.body) as Map);
              body = {'contract_version':1,'company_id':mode == 'wrong_company' ? 'other' : company,
                ...(sent!['p_values'] as Map),
                if (mode == 'wrong_result') 'tax_rate': 99,
                if (mode == 'invalid_money') 'overtime_hour_rate_yen': 1400.5};
              if (mode == 'actor_changed') {
                await client.auth.signOut(scope: SignOutScope.local);
              }
            }
          }
          return http.Response(jsonEncode(body), 200,
            headers:{'content-type':'application/json'}, request:req);
        }));
      addTearDown(client.dispose);
      await client.auth.signInWithPassword(email:'fixture@example.invalid',password:'fixture');
      final repo = CompanyRateSettingsRepository.forTesting(client);
      if (mode == 'missing_rpc') {
        await expectLater(repo.loadDefaults(company), throwsA(isA<PostgrestException>()));
        expect(calls, ['/rest/v1/rpc/read_company_rate_defaults']);
        return;
      }
      final before = await repo.loadDefaults(company);
      final result = repo.saveDefaults(expected:before,taxRate:8,welfareRate:15,
        overtimeHourRateYen:1400,earlyHourRateYen:1100,nightHourRateYen:1200,holidayDayRateYen:1300);
      if (mode == 'saved') {
        final after = await result;
        expect(after.taxRate, 8);
        expect(after.companyId, company);
      } else {
        await expectLater(result, throwsStateError);
      }
      expect(calls, ['/rest/v1/rpc/read_company_rate_defaults','/rest/v1/rpc/save_company_rate_defaults']);
      expect(sent!['p_expected'],values());
      expect((sent!['p_values'] as Map).keys.toSet(),values().keys.toSet());
      expect(jsonEncode(sent),isNot(contains('allowance_')));
    });
  }
}
