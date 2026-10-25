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
  int settingsStatus = 200, userStatus = 200;
  Object? settingsOverride;
  Completer<void>? holdUser, reachedUser;
  Completer<void>? holdWrite, reachedWrite;

  setUp(() async {
    requests = []; phoneEnabled = false; confirmed = true; phone = ''; role = 'owner';
    holdWrite = null; reachedWrite = null; needsNonce = false;
    settingsStatus = 200; userStatus = 200; settingsOverride = null;
    holdUser = null; reachedUser = null;
    network = MockClient((request) async {
      requests.add(request);
      dynamic value = {};
      if (request.url.path.endsWith('/settings')) {
        if (settingsStatus != 200) return http.Response('PRIVATE_SETTINGS_$actor', settingsStatus);
        value = settingsOverride ?? {'external': {'email': true, 'phone': phoneEnabled}};
      } else if (request.url.path.endsWith('/company_members')) {
        value = [{'company_id': 'synthetic-company', 'role': role}];
      } else if (request.url.path.endsWith('/user')) {
        if (request.method == 'GET') {
          reachedUser?.complete(); await holdUser?.future;
          if (userStatus != 200) return http.Response('PRIVATE_USER_$actor', userStatus);
        }
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
      authUrl: Uri.parse('https://enroll.invalid/auth/v1/'), publicKey: 'synthetic-public',
      transport: network, enablePhoneEnrollment: true);
  });
  tearDown(() async { repository.dispose(); await client.dispose(); network.close(); });

  test('default paused phone registration refuses SMS writes even when provider advertises enabled', () async {
    repository.dispose();
    repository=LoginMethodEnrollmentRepository(client,
      authUrl:Uri.parse('https://enroll.invalid/auth/v1/'),publicKey:'synthetic-public',transport:network);
    phoneEnabled=true;
    final original=client.auth.currentSession!.accessToken;
    final state=await repository.load();
    expect(state.phoneAvailable,true);expect(state.phoneRegistrationReady,false);
    expect(state.canRegisterPhone,false);expect(state.canSetPassword,true);
    await expectLater(repository.requestPhone('09012345678'),throwsStateError);
    await expectLater(repository.confirmPhone('123456'),throwsStateError);
    expect(requests.every((r)=>r.method=='GET'),true);
    expect(client.auth.currentSession!.accessToken,original);
    expect(client.auth.currentUser!.id,actor);
  });
  test('existing confirmed phone can still qualify password setup while registration is paused', () {
    const state=LoginMethodEnrollmentState(email:'',phone:'819012345678',
      emailConfirmed:false,phoneConfirmed:true,emailAvailable:false,phoneAvailable:true);
    expect(state.canRegisterPhone,false);expect(state.canSetPassword,true);
  });
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
  Future<LoginEnrollmentReadFailure> readFailure(LoginEnrollmentReadStage stage) async {
    try {
      await repository.load();
      fail('read must fail');
    } on LoginEnrollmentReadFailure catch (error) {
      expect(error.stage, stage);
      expect(error.toString(), 'LoginEnrollmentReadFailure(${stage.name})');
      expect(error.toString(), isNot(contains(actor)));
      expect(error.message, isNot(contains(actor)));
      expect(error.toString(), isNot(contains('PRIVATE_')));
      expect(error.message, isNot(contains('PRIVATE_')));
      return error;
    }
  }

  test('provider transport failure is sanitized and phone OFF recovers without OTP', () async {
    final token = client.auth.currentSession!.accessToken;
    settingsStatus = 503;
    await readFailure(LoginEnrollmentReadStage.providerSettings);
    settingsStatus = 200;
    final state = await repository.load();
    expect(state.phone, isEmpty); expect(state.phoneAvailable, false);
    expect(state.canSetPassword, true);
    expect(requests.every((r) => r.method == 'GET'), true);
    expect(client.auth.currentSession!.accessToken, token);
  });

  test('wrong public provider response shape is a separate sanitized stage', () async {
    settingsOverride = {'external': 'PRIVATE_SHAPE_$actor'};
    await readFailure(LoginEnrollmentReadStage.providerShape);
    expect(requests.every((r) => r.method == 'GET'), true);
  });

  test('verified user read failure is distinct from settings and never exposes response', () async {
    userStatus = 404;
    await readFailure(LoginEnrollmentReadStage.verifiedUser);
    expect(requests.any((r) => r.url.path.endsWith('/settings')), false);
    expect(requests.every((r) => r.method == 'GET'), true);
  });

  test('missing initial session is a fixed session-stage failure without API calls', () async {
    repository.dispose();
    final fresh = SupabaseClient('https://enroll.invalid', 'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: network);
    repository = LoginMethodEnrollmentRepository(fresh,
      authUrl: Uri.parse('https://enroll.invalid/auth/v1/'), publicKey: 'synthetic-public', transport: network);
    addTearDown(fresh.dispose);
    await readFailure(LoginEnrollmentReadStage.session);
    expect(requests, isEmpty);
  });

  test('session change during verified user read reports session stage and preserves new login', () async {
    holdUser = Completer<void>(); reachedUser = Completer<void>();
    final operation = repository.load();
    final rejected = expectLater(operation, throwsA(isA<LoginEnrollmentReadFailure>()
      .having((e) => e.stage, 'stage', LoginEnrollmentReadStage.session)));
    await reachedUser!.future;
    await client.auth.setInitialSession(session(other));
    final newToken = client.auth.currentSession!.accessToken;
    holdUser!.complete(); await rejected;
    expect(client.auth.currentUser!.id, other);
    expect(client.auth.currentSession!.accessToken, newToken);
    expect(requests.any((r) => r.url.path.endsWith('/settings')), false);
    expect(requests.every((r) => r.method == 'GET'), true);
  });

}
