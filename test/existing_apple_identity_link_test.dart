import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/existing_apple_identity_link.dart';

const actor = '91000000-0000-4000-8000-000000000001';
const other = '91000000-0000-4000-8000-000000000002';
Map<String, dynamic> identity(String id, String provider) => {
  'id': id, 'identity_id': id, 'user_id': actor, 'provider': provider,
  'identity_data': <String,dynamic>{}, 'created_at': '2026-10-17T00:00:00Z',
  'last_sign_in_at': '2026-10-17T00:00:00Z',
};
Map<String,dynamic> user(String id, bool apple) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-10-17T00:00:00Z',
  'app_metadata': <String,dynamic>{}, 'user_metadata': <String,dynamic>{},
  'identities': [identity('google-identity', 'google'),
    if (apple) identity('apple-identity', 'apple')],
};
Map<String,dynamic> session(String id) => {
 'access_token': 'synthetic-$id', 'refresh_token': 'synthetic-refresh',
 'token_type':'bearer','expires_in':3600,'user':user(id,false),
};
class Fixture {
 Fixture() {
  client=SupabaseClient('https://apple-preservation-fixture.invalid','public_fixture',
   authOptions: AuthClientOptions(autoRefreshToken:false),
   httpClient:MockClient((r) async {
    expect(r.url.host,'apple-preservation-fixture.invalid'); calls.add(r);
    Object result;
    if(r.url.path=='/auth/v1/token') {
     final body=jsonDecode(r.body) as Map;
     result=session(body['email']=='other@example.invalid'?other:actor);
    } else if(r.url.path=='/auth/v1/user') {
     expect(r.headers['Authorization'],'Bearer synthetic-$actor');
     if(switchDuringRead) {
      switchDuringRead=false;
      await client.auth.signInWithPassword(email:'other@example.invalid',password:'synthetic');
     }
     result=user(actor,apple);
    } else if(r.url.path=='/rest/v1/company_members') {
     expect(r.headers['Authorization'],'Bearer synthetic-$actor');
     expect(r.url.queryParameters['user_id'],'eq.$actor');
     result=[{'company_id':'synthetic-company','role':role}];
    } else { throw StateError('Unexpected fixture request'); }
    return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:r);
   }));
 }
 late final SupabaseClient client;
 bool apple=false, switchDuringRead=false;
 String role='owner';
 final calls=<http.Request>[];
 Future<void> login() async { await client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic'); }
}
void main(){
 test('existing Google identity and company role survive read-only Apple-added verification',()async{
  final f=Fixture();await f.login();final service=ExistingAppleIdentityLink(f.client);
  final before=await service.capture();f.apple=true;await service.verifyAdded(before);
  expect(f.calls.where((r)=>r.url.path!='/auth/v1/token').every((r)=>r.method=='GET'),true);
  expect(f.calls.any((r)=>r.url.path.contains('identities/authorize')||r.url.path.endsWith('/signup')),false);
  await f.client.dispose();
 });
 test('browser/no callback and changed role cannot be verified as success',()async{
  final f=Fixture();await f.login();final service=ExistingAppleIdentityLink(f.client);
  final before=await service.capture();
  await expectLater(service.verifyAdded(before),throwsA(isA<AppleIdentityPreservationRejected>()));
  f.apple=true;f.role='viewer';
  await expectLater(service.verifyAdded(before),throwsA(isA<AppleIdentityPreservationRejected>()));
  await f.client.dispose();
 });
 test('captured getUser does not authorize late actor A after actual SDK switches to B',()async{
  final f=Fixture();await f.login();final service=ExistingAppleIdentityLink(f.client);
  f.switchDuringRead=true;
  await expectLater(service.capture(),throwsA(isA<AppleIdentityPreservationRejected>()));
  expect(f.client.auth.currentUser!.id,other);
  expect(f.calls.any((r)=>r.url.path=='/rest/v1/company_members'),false);
  await f.client.dispose();
 });
}
