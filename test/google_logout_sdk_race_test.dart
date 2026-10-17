import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Diagnostic for the pinned SDK; this is not a new product logout operation.
class _DelayedPkceStorage extends GotrueAsyncStorage {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override Future<String?> getItem({required String key}) async => null;
  @override Future<void> setItem({required String key, required String value}) async {}
  @override Future<void> removeItem({required String key}) async {
    entered.complete();
    await release.future;
  }
}
Map<String,dynamic> _session(String id) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':id,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token':'synthetic-$id','token_type':'bearer','expires_in':3600,
    'user':{'id':id,'aud':'authenticated','created_at':'2026-10-16T00:00:00Z','app_metadata':<String,dynamic>{},'user_metadata':<String,dynamic>{}}};
}
void main() {
  test('pinned logout emits signedOut with later actor after asynchronous PKCE removal: new UI remains HOLD', () async {
    const actorA='20000000-0000-0000-0000-000000000001';
    const actorB='20000000-0000-0000-0000-000000000002';
    final storage=_DelayedPkceStorage();
    final requests=<http.Request>[]; final events=<AuthState>[];
    final client=SupabaseClient('https://google-logout-fixture.invalid','public_fixture',
      authOptions:AuthClientOptions(autoRefreshToken:false,pkceAsyncStorage:storage),
      httpClient:MockClient((r) async {
        expect(r.url.host,'google-logout-fixture.invalid'); requests.add(r);
        if(r.url.path=='/auth/v1/token') {
          final body=jsonDecode(r.body) as Map;
          final id=body['phone']=='+819012345678' ? actorA : actorB;
          return http.Response(jsonEncode(_session(id)),200,headers:{'content-type':'application/json'},request:r);
        }
        if(r.url.path=='/auth/v1/logout') return http.Response('{}',200,request:r);
        throw StateError('Unexpected synthetic request');
      }));
    final subscription=client.auth.onAuthStateChange.listen(events.add);
    await client.auth.signInWithPassword(phone:'+819012345678',password:'synthetic-A');
    final tokenA=client.auth.currentSession!.accessToken;
    final logout=client.auth.signOut(scope:SignOutScope.local);
    await storage.entered.future;
    expect(client.auth.currentSession,isNull);
    await client.auth.signInWithPassword(phone:'+819012345679',password:'synthetic-B');
    expect(client.auth.currentUser!.id,actorB);
    storage.release.complete(); await logout;
    await Future<void>.delayed(Duration.zero);
    final request=requests.singleWhere((r)=>r.url.path=='/auth/v1/logout');
    expect(request.headers['Authorization'],'Bearer $tokenA');
    expect(request.url.queryParameters['scope'],'local');
    expect(client.auth.currentUser!.id,actorB);
    // Memory B survives, but the late signedOut event carries B. A new helper
    // cannot safely promise isolation of the SDK's global persistence listeners.
    expect(events.any((e)=>e.event==AuthChangeEvent.signedOut && e.session?.user.id==actorB),isTrue);
    expect(requests.where((r)=>r.url.path=='/auth/v1/signup'||r.url.path=='/auth/v1/user'),isEmpty);
    await subscription.cancel(); await client.dispose();
  });
}
