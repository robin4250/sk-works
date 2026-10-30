import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/auth/secure_onboarding_repository.dart';
import 'package:sk_works/data/supabase_auth_repository.dart';
import 'package:sk_works/features/profile/profile_repository.dart';

const actor = '60000000-0000-0000-0000-000000000001';
const other = '60000000-0000-0000-0000-000000000002';
const sid = '60000000-0000-0000-0000-000000000003';
const nextSid = '60000000-0000-0000-0000-000000000004';
Map<String,dynamic> user([String uid = actor]) => {'id':uid,'aud':'authenticated',
  'app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{},
  'email':'fixture@example.invalid','created_at':'2026-01-01T00:00:00Z'};
Map<String,dynamic> session({String uid = actor, String sessionId = sid, int generation = 1}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':uid,'session_id':sessionId,'iat':generation,'exp':4102444800})}.${base64Url.encode(List<int>.filled(32,7)).replaceAll('=', '')}',
    'refresh_token':'synthetic-$sessionId','token_type':'bearer','expires_in':3600,'user':user(uid)};
}
class Wire {
  Wire() {
    client = SupabaseClient('https://app-auth-fixture.invalid','public-fixture',
      authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((request) async {
        calls.add(request);
        final value = await respond(request);
        return http.Response.bytes(value.bodyBytes,value.statusCode,headers:value.headers,request:request);
      }));
    auth = AppAuthMutationGateway.forClient(client);
    onboarding = SecureOnboardingRepository.forClient(client);
    legacy = SupabaseAuthRepository(client);
  }
  late final SupabaseClient client;
  late final AppAuthMutationGateway auth;
  late final SecureOnboardingRepository onboarding;
  late final SupabaseAuthRepository legacy;
  final calls = <http.Request>[];
  Future<http.Response> Function(http.Request) respond = (request) async {
    if(request.url.path.endsWith('/logout')) return http.Response('',204);
    if(request.url.path.endsWith('/user')) return json(user());
    if(request.url.path.endsWith('/company_members')) return json([{'company_id':other,'role':'viewer'}]);
    return json(session());
  };
  Future<void> sent(int count) async {
    for (var i = 0; i < 30 && calls.length < count; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(calls.length, greaterThanOrEqualTo(count));
  }
  static http.Response json(Object value) => http.Response(jsonEncode(value),200,headers:{'content-type':'application/json'});
  Future<void> seed({String uid = actor, String sessionId = sid, int generation = 1}) async {
    await client.auth.setInitialSession(jsonEncode(session(uid:uid,sessionId:sessionId,generation:generation)));
    await Future<void>.delayed(Duration.zero);
  }
}
void main() {
 late Wire w;
 setUp(() { w=Wire(); });
 tearDown(() async { await w.client.dispose(); });

 test('inspection is not SDK setSession CAS: logout cannot cancel a raw pending save',() async {
  await w.seed();
  final inspection=await w.auth.inspectCurrentSession();
  final userReply=Completer<http.Response>();
  final started=Completer<void>();
  w.respond=(request) {
   if(request.url.path.endsWith('/user')) {started.complete();return userReply.future;}
   return Future.value(http.Response('',204));
  };
  // Deliberately unsafe baseline, never a production adoption implementation.
  final raw=w.client.auth.setSession('synthetic-$nextSid',accessToken:session(sessionId:nextSid)['access_token'] as String);
  await started.future;
  await w.auth.signOut();
  expect(inspection.isCurrent,isFalse);
  expect(w.client.auth.currentSession,isNull);
  userReply.complete(Wire.json(user()));
  await raw;await Future<void>.delayed(Duration.zero);
  expect(w.client.auth.currentSession?.refreshToken,'synthetic-$nextSid',
   reason:'Pinned SDK finishes its internal save after logout; a lease is not CAS');
  expect(inspection.isCurrent,isFalse);
  expect(w.calls.where((r)=>r.url.path.endsWith('/user')),hasLength(1));
 });

 test('inspection cannot cancel delayed SDK save after another account wins',() async {
  await w.seed();
  final inspection=await w.auth.inspectCurrentSession();
  final userReply=Completer<http.Response>();
  final started=Completer<void>();
  w.respond=(request) {started.complete();return userReply.future;};
  final raw=w.client.auth.setSession('synthetic-$nextSid',accessToken:session(sessionId:nextSid)['access_token'] as String);
  await started.future;
  await w.seed(uid:other,sessionId:nextSid,generation:3);
  expect(inspection.isCurrent,isFalse);
  expect(w.client.auth.currentUser?.id,other);
  userReply.complete(Wire.json(user()));
  await raw;await Future<void>.delayed(Duration.zero);
  expect(w.client.auth.currentUser?.id,actor,
   reason:'External SDK writers can overwrite each other before observer validation');
  expect(inspection.isCurrent,isFalse);
 });

 test('safe current preparation boundary retires before any attempted adoption',() async {
  await w.seed();
  final inspection=await w.auth.inspectCurrentSession();
  await w.seed(sessionId:nextSid);
  expect(inspection.isCurrent,isFalse);
  // Existing consumers must stop here: no successor credential goes to global SDK.
  expect(w.calls,isEmpty);
  await expectLater(inspection.invalidated,completes);
 });
}
