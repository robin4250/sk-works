import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/login_method_enrollment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '20000000-0000-0000-0000-000000000001';
const other = '20000000-0000-0000-0000-000000000002';

Map<String, dynamic> user(String id, {bool confirmed = true, String phone = ''}) => {
  'id': id, 'aud': 'authenticated', 'email': 'existing@example.invalid', 'phone': phone,
  'email_confirmed_at': confirmed ? '2026-01-01T00:00:00Z' : null,
  'phone_confirmed_at': phone.isEmpty ? null : '2026-01-01T00:00:00Z',
  'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {'provider': 'google'},
  'user_metadata': {}, 'identities': [
    {'id': '$id-google', 'identity_id': id, 'user_id': id, 'provider': 'google',
      'identity_data': {'sub': id}, 'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z'}],
};

String session(String id, {int age = 0}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({'access_token': '${part({'alg':'HS256'})}.${part({
    'sub':id,'exp':now+3600,'amr':[{'method':'oauth','timestamp':now-age}]})}.synthetic',
    'refresh_token':'synthetic', 'token_type':'bearer', 'expires_in':3600, 'user':user(id)});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late LoginMethodEnrollmentRepository repository;
  late List<http.Request> requests;
  late MockClient network;
  bool phoneEnabled = false, confirmed = true, needsNonce = false;
  String phone = '', role = 'owner';
  Completer<void>? holdWrite, reachedWrite;

  setUp(() async {
    requests = []; phoneEnabled = false; confirmed = true; phone = ''; role = 'owner';
    holdWrite = null; reachedWrite = null; needsNonce = false;
    network = MockClient((request) async {
      requests.add(request);
      dynamic value = {};
      if (request.url.path.endsWith('/settings')) {
        value = {'external': {'email': true, 'phone': phoneEnabled}};
      } else if (request.url.path.endsWith('/company_members')) {
        value = [{'company_id': 'synthetic-company', 'role': role}];
      } else if (request.url.path.endsWith('/user')) {
        if (request.method == 'PUT') {
          if (needsNonce && jsonDecode(request.body)['nonce'] != '123456') {
            return http.Response('{"code":"reauthentication_needed"}', 400, headers: {'content-type':'application/json'});
          }
          reachedWrite?.complete();
          await holdWrite?.future;
        }
        value = user(actor, confirmed: confirmed, phone: phone);
      } else if (request.url.path.endsWith('/verify')) {
        phone = '+819012345678';
        value = {'user': user(actor, phone: phone)};
      } else if (request.url.path.endsWith('/reauthenticate')) {
        return http.Response('', 204);
      } else if (!request.url.path.endsWith('/logout')) {
        throw StateError('unexpected fixture route');
      }
      return http.Response(jsonEncode(value), 200,
        headers: {'content-type': 'application/json'}, request: request);
    });
    client = SupabaseClient('https://enroll.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: network);
    await client.auth.setInitialSession(session(actor));
    repository = LoginMethodEnrollmentRepository(client,
      authUrl: Uri.parse('https://enroll.invalid/auth/v1/'), publicKey: 'synthetic-public', transport: network);
  });
  tearDown(() async { repository.dispose(); await client.dispose(); network.close(); });

  test('server-confirmed email enables primary password; unavailable phone stays unavailable', () async {
    final state = await repository.load();
    expect(state.canSetPassword, true);
    expect(state.phoneAvailable, false);
    expect(state.phone, isEmpty);
    expect(client.auth.currentUser!.id, actor);
  });

  test('primary password uses captured user endpoint only and preserves Google and company', () async {
    final original = client.auth.currentSession!.accessToken;
    await repository.setPrimaryPassword('First-password-fixture');
    final writes = requests.where((r) => r.method != 'GET').toList();
    expect(writes, hasLength(1));
    expect(writes.single.method, 'PUT');
    expect(writes.single.url.path, '/auth/v1/user');
    expect(writes.single.headers['authorization'], 'Bearer $original');
    expect(jsonDecode(writes.single.body), {'password':'First-password-fixture'});
    expect(requests.any((r) => r.url.path.contains('secondary') || r.url.path.contains('signup') ||
      r.url.path.endsWith('/token')), false);
    expect(client.auth.currentUser!.id, actor);
    expect((await repository.load()).emailConfirmed, true);
  });

  test('server-required password nonce uses existing session and no login or signup', () async {
    needsNonce = true;
    await expectLater(repository.setPrimaryPassword('First-password-fixture'),
      throwsA(isA<PrimaryPasswordReauthenticationRequired>()));
    await repository.requestPrimaryPasswordCode();
    await repository.setPrimaryPassword('First-password-fixture', nonce: '123456');
    expect(requests.where((r) => r.url.path.endsWith('/reauthenticate')), hasLength(1));
    expect(client.auth.currentUser!.id, actor);
    expect(requests.any((r) => r.url.path.endsWith('/token') || r.url.path.contains('/signup')), false);
  });

  test('unconfirmed identifiers stop before credential write', () async {
    confirmed = false;
    await expectLater(repository.setPrimaryPassword('First-password-fixture'), throwsStateError);
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  test('provider OFF prevents sending a phone OTP', () async {
    await expectLater(repository.requestPhone('09012345678'), throwsStateError);
    expect(requests.where((r) => r.method != 'GET'), isEmpty);
  });

  test('phone is registered only after phone-change OTP and server reread', () async {
    phoneEnabled = true;
    await repository.requestPhone('090-1234-5678');
    expect((await repository.load()).phoneConfirmed, false);
    await repository.confirmPhone('123456');
    final verify = requests.singleWhere((r) => r.url.path.endsWith('/verify'));
    expect(jsonDecode(verify.body), {'type':'phone_change','phone':'+819012345678','token':'123456'});
    expect((await repository.load()).phoneConfirmed, true);
    expect(client.auth.currentUser!.id, actor);
  });

  test('cancelled phone operation cannot verify a stale code', () async {
    phoneEnabled = true;
    await repository.requestPhone('09012345678');
    repository.cancelPhone();
    await expectLater(repository.confirmPhone('123456'), throwsStateError);
    expect(requests.where((r) => r.url.path.endsWith('/verify')), isEmpty);
  });

  test('logout then same-user login cannot resurrect an in-flight credential save', () async {
    holdWrite = Completer<void>(); reachedWrite = Completer<void>();
    final operation = repository.setPrimaryPassword('First-password-fixture');
    final rejection = expectLater(operation, throwsStateError);
    await reachedWrite!.future;
    await client.auth.signOut(scope: SignOutScope.local);
    await client.auth.setInitialSession(session(actor));
    holdWrite!.complete();
    await rejection;
    expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
  });

  test('switching accounts never writes credentials to the newer account', () async {
    final original = client.auth.currentSession!.accessToken;
    holdWrite = Completer<void>(); reachedWrite = Completer<void>();
    final operation = repository.setPrimaryPassword('First-password-fixture');
    final rejection = expectLater(operation, throwsStateError);
    await reachedWrite!.future;
    await client.auth.setInitialSession(session(other));
    holdWrite!.complete();
    await rejection;
    expect(requests.singleWhere((r) => r.method == 'PUT').headers['authorization'], 'Bearer $original');
    expect(client.auth.currentUser!.id, other);
  });
}
