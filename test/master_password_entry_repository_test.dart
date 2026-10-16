import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/settings/master_password_entry_repository.dart';
const _actor = '60000000-0000-0000-0000-000000000001';
const _sid = '60000000-0000-0000-0000-000000000002';
const _request = '60000000-0000-0000-0000-000000000003';
const _challenge = '60000000-0000-0000-0000-000000000004';
Map<String,dynamic> _session() {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':_actor,'role':'authenticated','session_id':_sid,'exp':DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token':'synthetic-refresh','token_type':'bearer','expires_in':3600,
    'user':{'id':_actor,'aud':'authenticated','created_at':'2026-10-16T00:00:00Z','app_metadata':{'providers':['google']},'user_metadata':<String,dynamic>{}}};
}
void main() {
  for (final malformed in [false, true]) {
    test('pinned SDK dedicated unlock exact target/bearer, malformed reply rejected=$malformed, never shared fallback', () async {
      final requests = <http.Request>[];
      final session = _session();
      final client = SupabaseClient('https://master-entry-fixture.invalid','public_fixture',
        authOptions: AuthClientOptions(autoRefreshToken:false),
        httpClient:MockClient((r) async {
          expect(r.url.host,'master-entry-fixture.invalid'); requests.add(r);
          expect(r.headers['Authorization'],'Bearer ${session['access_token']}');
          final name=r.url.path.split('/').last;
          Map<String,dynamic> result;
          switch(name) {
            case 'master_password_capability': result={'protocol':'sko-master-password-v1','enabled':true};
            case 'current_master_password_status': result={'protocol':'sko-master-password-v1','status':'ready','configured':true,'credential_version':1};
            case 'begin_master_password_operation':
              expect(jsonDecode(r.body),{'p_device_key':'synthetic-device-key-longer-than-32-characters','p_operation':'unlock','p_expected_version':1,'p_request_id':_request});
              result={'protocol':'sko-master-password-v1','status':'challenge','operation':'unlock','expected_version':1,'request_id':_request,'challenge_id':_challenge,'nonce':'a'*64,'expires_at':DateTime.now().toUtc().add(const Duration(seconds:120)).toIso8601String()};
            case 'verify_master_password_operation':
              expect(jsonDecode(r.body),{'p_device_key':'synthetic-device-key-longer-than-32-characters','p_challenge_id':_challenge,'p_nonce':'a'*64,'p_password':'synthetic-dedicated-secret','p_request_id':_request});
              result={'protocol':'sko-master-password-v1','status':'verified','operation':'unlock','request_id':_request,'credential_version':malformed ? 2 : 1,'configured':true};
            default: throw StateError('Unexpected synthetic request');
          }
          return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:r);
        }));
      await client.auth.setInitialSession(jsonEncode(session));
      final repository=MasterPasswordEntryRepository(client,deviceKey:'synthetic-device-key-longer-than-32-characters');
      final captured=repository.binding!;
      expect((await repository.read(captured)).version,1);
      final challenge=await repository.beginUnlock(captured,1,_request);
      final verify=repository.verifyUnlock(captured,1,_request,challenge,'synthetic-dedicated-secret');
      if(malformed) { await expectLater(verify,throwsA(isA<FormatException>())); } else { await verify; }
      expect(requests.length,4);
      expect(requests.any((r)=>r.url.path.contains('verify_secondary')||r.url.path.contains('set_secondary')||r.url.path.contains('/auth/v1/user')||r.url.path.contains('/signup')),isFalse);
      expect(client.auth.currentUser!.id,_actor); await client.dispose();
    });
  }
  test('ON unknown RPC/permission failures never fall back to shared verifier', () async {
    final requests=<http.Request>[]; final session=_session();
    final client=SupabaseClient('https://master-entry-fixture.invalid','public_fixture',
      authOptions:AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
        expect(r.url.host,'master-entry-fixture.invalid'); requests.add(r);
        return http.Response(jsonEncode({'code':'42501','message':'synthetic denied'}),403,headers:{'content-type':'application/json'},request:r);
      }));
    await client.auth.setInitialSession(jsonEncode(session));
    final repository=MasterPasswordEntryRepository(client,deviceKey:'synthetic-device-key-longer-than-32-characters');
    await expectLater(repository.read(repository.binding!),throwsA(isA<PostgrestException>()));
    expect(requests.length,1); expect(requests.single.url.path.endsWith('master_password_capability'),isTrue);
    await client.dispose();
  });
}
