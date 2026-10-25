import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/operation_reauthentication_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actorA = '10000000-0000-0000-0000-000000000001';
const actorB = '10000000-0000-0000-0000-000000000002';
const sessionA = '20000000-0000-0000-0000-000000000001';
const sessionB = '20000000-0000-0000-0000-000000000002';
String token(String actor, String session, {int revision = 0}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({
    'sub': actor, 'session_id': session, 'role': 'authenticated', 'fixture_revision':revision,
    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  })}.synthetic';
}
http.Response jsonResponse(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});
class Fixture {
  Fixture() {
    client = SupabaseClient('https://fixture.invalid', 'public_fixture',
      httpClient: MockClient((request) async {
        final response = await handle(request);
        // PostgREST 2.9.1 reads response.request for HEAD/content parsing.
        return http.Response.bytes(response.bodyBytes, response.statusCode,
          headers: response.headers, request: request, reasonPhrase: response.reasonPhrase);
      }), authOptions: const AuthClientOptions(autoRefreshToken: false));
    repository = OperationReauthenticationRepository(client);
  }
  late final SupabaseClient client;
  late final OperationReauthenticationRepository repository;
  String actor = actorA;
  String session = sessionA;
  int capabilityStatus = 200;
  int tokenRevision = 0;
  bool capabilityNetworkFailure = false;
  Object capability = {'protocol': 'sko-reauthentication-v1',
    'secondary_password': true, 'master_feature': false, 'master_security': false};
  Map<String, dynamic>? proofResponse;
  Future<void> Function()? duringProof;
  final mutations = <http.Request>[];
  final targets = <http.Request>[];
  final bodies = <Map<String, dynamic>>[];
  final headers = <String>[];
  Future<void> login() => client.auth.signInWithPassword(phone: '+810000000000', password: 'synthetic')
      .then((_) {});
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/auth/v1/token') {
      return jsonResponse({'access_token': token(actor, session,revision:++tokenRevision), 'refresh_token': 'synthetic-refresh',
        'expires_in': 3600, 'token_type': 'bearer', 'user': {'id': actor,
          'aud': 'authenticated', 'app_metadata': {}, 'user_metadata': {},
          'created_at': '2026-10-16T00:00:00Z'}});
    }
    if (request.url.path.endsWith('/reauthentication_capabilities')) {
      if (capabilityNetworkFailure) throw StateError('synthetic connection failed');
      return jsonResponse(capability, capabilityStatus);
    }
    if (request.url.path.endsWith('/attendance_management_reauthentication_target')) {
      targets.add(request);
      return jsonResponse({'company_id': '30000000-0000-0000-0000-000000000001',
        'action': (jsonDecode(request.body) as Map)['p_action'], 'items_sha256': List.filled(64, 'a').join()});
    }
    if (request.url.path.endsWith('/force_manage_attendance') || request.url.path.endsWith('/force_manage_attendance_with_proof')) {
      mutations.add(request);return jsonResponse(1);
    }
    if (request.url.path == '/functions/v1/reauthenticate-operation') {
      bodies.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      headers.add(request.headers['authorization'] ?? '');
      await duringProof?.call();
      return jsonResponse(proofResponse ?? {'protocol': 'sko-reauthentication-v1',
        'proof': List.filled(64, 'a').join(),
        'expiresAt': DateTime.now().add(const Duration(seconds: 120)).toIso8601String(),
        'operation': (jsonDecode(request.body) as Map)['operation'],
        'target': (jsonDecode(request.body) as Map)['target']});
    }
    throw StateError('Unexpected fixture endpoint ${request.url.path}');
  }
  Future<String> proof() => repository.requestProof(password: 'synthetic-primary',
    operation: 'secondary_password.replace', target: {'user_id': actorA});
}
void main() {
  test('capability ON/OFF passes only explicit well-formed boolean contract', () async {
    final f = Fixture();addTearDown(f.client.dispose);await f.login();
    expect((await f.repository.capabilities())['secondary_password'], true);
    f.capability = {'protocol': 'sko-reauthentication-v1',
      'secondary_password': false, 'master_feature': false, 'master_security': false};
    expect((await f.repository.capabilities()).values.every((v) => !v), true);
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('only missing RPC PGRST202 preserves legacy capability', () async {
    final f = Fixture();addTearDown(f.client.dispose);await f.login();
    f.capabilityStatus = 404;f.capability = {'code': 'PGRST202', 'message': 'synthetic missing RPC'};
    expect((await f.repository.capabilities()).values.every((v) => !v), true);
    f.capabilityStatus = 403;f.capability = {'code': '42501', 'message': 'synthetic permission denied'};
    await expectLater(f.repository.capabilities(), throwsA(isA<PostgrestException>()));
    f.capabilityStatus = 200;f.capability = {'protocol': 'sko-reauthentication-v1', 'secondary_password': true};
    await expectLater(f.repository.capabilities(), throwsStateError);
    f.capabilityNetworkFailure = true;
    await expectLater(f.repository.capabilities(), throwsA(anything));
  }, timeout: const Timeout(Duration(seconds: 30)));
  test('proof request uses original bearer and exact operation target; only nonce returned', () async {
    final f = Fixture();addTearDown(f.client.dispose);await f.login();
    final original = f.client.auth.currentSession!.accessToken;
    expect(await f.proof(), List.filled(64, 'a').join());
    expect(f.headers.single, 'Bearer $original');
    expect(f.bodies.single, {'password': 'synthetic-primary',
      'operation': 'secondary_password.replace', 'target': {'user_id': actorA}});
  }, timeout: const Timeout(Duration(seconds: 30)));
  for (final sameActor in [true, false]) {
    test('actor/session switch during proof rejects response ($sameActor)', () async {
      final f = Fixture();addTearDown(f.client.dispose);await f.login();
      f.duringProof = () async {f.actor = sameActor ? actorA : actorB;f.session = sessionB;await f.login();};
      await expectLater(f.proof(), throwsStateError);
    }, timeout: const Timeout(Duration(seconds: 30)));
  }
  for(final sameActor in [true,false]) {
    test('session history cannot restore an old pending proof ($sameActor)', () async {
      final f=Fixture();addTearDown(f.client.dispose);await f.login();
      f.duringProof=() async {
        f.actor=sameActor?actorA:actorB;f.session=sessionB;await f.login();
        f.actor=actorA;f.session=sessionA;await f.login();
      };
      await expectLater(f.proof(),throwsStateError);
      expect(f.client.auth.currentUser!.id,actorA);
      expect(f.bodies,hasLength(1)); // no automatic issuance retry
      f.duringProof=null;
      expect(await f.proof(),'a'*64); // a fresh explicit operation is independent
      expect(f.bodies,hasLength(2));
    },timeout:const Timeout(Duration(seconds:30)));
  }
  test('same server session JWT renewal keeps a pending proof valid', () async {
    final f=Fixture();addTearDown(f.client.dispose);await f.login();
    final original=f.client.auth.currentSession!.accessToken;
    f.duringProof=() async {await f.login();};
    expect(await f.proof(),'a'*64);
    expect(f.client.auth.currentSession!.accessToken,isNot(original));
    expect(f.headers.single,'Bearer $original');
    expect(f.bodies,hasLength(1));
  },timeout:const Timeout(Duration(seconds:30)));
  test('malformed, expired, overlong, other operation and target proofs rejected', () async {
    final f = Fixture();addTearDown(f.client.dispose);await f.login();
    final valid = {'protocol': 'sko-reauthentication-v1', 'proof': List.filled(64, 'a').join(),
      'expiresAt': DateTime.now().add(const Duration(seconds: 120)).toIso8601String(),
      'operation': 'secondary_password.replace', 'target': {'user_id': actorA}};
    for (final change in [
      {'proof': 'short'}, {'operation': 'master.feature.set'}, {'target': {'user_id': actorB}},
      {'expiresAt': DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String()},
      {'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toIso8601String()},
    ]) {f.proofResponse = {...valid, ...change};await expectLater(f.proof(), throwsStateError);}
  }, timeout: const Timeout(Duration(seconds: 30)));
  Future<int> manage(Fixture f, Future<String?> Function() password,
      {List<Map<String,dynamic>>? items}) => f.repository.manageAttendance(
        action: 'upsert', items: items ?? [{'worker_id': actorA, 'date': '2026-10-26'}],
        requestPassword: password);
  test('attendance OFF and missing RPC preserve old writer without password dialog', () async {
    for (final missing in [false,true]) {
      final f=Fixture();addTearDown(f.client.dispose);await f.login();
      if(missing){f.capabilityStatus=404;f.capability={'code':'PGRST202','message':'synthetic missing RPC'};}
      expect(await manage(f,() async => throw StateError('no dialog')),1);
      expect(f.mutations.single.url.path.endsWith('/force_manage_attendance'),true);
      expect(f.targets,isEmpty);expect(f.bodies,isEmpty);
    }
  });
  test('attendance ON uses exact target/second password/proof and immutable items', () async {
    final f=Fixture();addTearDown(f.client.dispose);await f.login();
    (f.capability as Map)['attendance_management']=true;
    final items=<Map<String,dynamic>>[{'worker_id':actorA,'date':'2026-10-26'}];
    expect(await manage(f,() async {items.single['date']='2026-10-27';return 'synthetic-secondary';},items:items),1);
    expect(f.bodies.single['operation'],'attendance.manage');
    expect(f.bodies.single['password'],'synthetic-secondary');
    expect(f.mutations.single.url.path.endsWith('/force_manage_attendance_with_proof'),true);
    expect((jsonDecode(f.mutations.single.body) as Map)['p_items'],[{'worker_id':actorA,'date':'2026-10-26'}]);
    expect(f.mutations.single.headers['authorization'],'Bearer ${f.client.auth.currentSession!.accessToken}');
  });
  test('attendance ON cancel and capability failure never fall back to old mutation', () async {
    final f=Fixture();addTearDown(f.client.dispose);await f.login();
    (f.capability as Map)['attendance_management']=true;
    await expectLater(manage(f,() async => null),throwsStateError);
    expect(f.bodies,isEmpty);expect(f.mutations,isEmpty);
    f.capabilityNetworkFailure=true;
    await expectLater(manage(f,() async => 'synthetic'),throwsA(anything));
    expect(f.mutations,isEmpty);
  });
  test('attendance whole dialog history rejects A-B-A before requesting proof', () async {
    final f=Fixture();addTearDown(f.client.dispose);await f.login();
    (f.capability as Map)['attendance_management']=true;
    await expectLater(manage(f,() async {
      f.actor=actorB;f.session=sessionB;await f.login();
      f.actor=actorA;f.session=sessionA;await f.login();return 'synthetic-secondary';
    }),throwsStateError);
    expect(f.bodies,isEmpty);expect(f.mutations,isEmpty);
  });
  test('attendance same-session token refresh uses refreshed bearer and one proof mutation', () async {
    final f=Fixture();addTearDown(f.client.dispose);await f.login();
    (f.capability as Map)['attendance_management']=true;
    expect(await manage(f,() async {await f.login();return 'synthetic-secondary';}),1);
    expect(f.mutations.single.headers['authorization'],'Bearer ${f.client.auth.currentSession!.accessToken}');
  });

}

