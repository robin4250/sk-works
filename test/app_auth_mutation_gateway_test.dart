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
  setUp(() { w = Wire(); });
  tearDown(() async { await w.client.dispose(); });

  test('actual onboarding email and phone/password use shared SDK gateway',() async {
    await w.onboarding.signInWithEmail(email:' fixture@example.invalid ',password:'synthetic');
    await w.onboarding.signInWithPhone(phone:'09012345678',password:'synthetic');
    expect(w.client.auth.currentUser?.id,actor);
    expect(w.calls.where((r)=>r.url.path.endsWith('/token')),hasLength(2));
    expect(jsonDecode(w.calls.last.body)['phone'],'+819012345678');
  });
  test('onboarding forwards each challenge to Auth once and never reuses it implicitly', () async {
    final tokens = ['email-challenge', 'phone-challenge', 'signup-challenge', 'verify-challenge'];
    await w.onboarding.signInWithEmail(email: 'fixture@example.invalid', password: 'synthetic', captchaToken: tokens[0]);
    await w.onboarding.signInWithPhone(phone: '09012345678', password: 'synthetic', captchaToken: tokens[1]);
    await w.onboarding.registerAdmin(phone: '09012345678', password: 'synthetic', captchaToken: tokens[2]);
    await w.onboarding.verifySmsCode(phone: '09012345678', code: '123456', captchaToken: tokens[3]);
    final authCalls = w.calls.where((r) => r.url.path.endsWith('/token') || r.url.path.endsWith('/signup') || r.url.path.endsWith('/verify')).toList();
    expect(authCalls, hasLength(4));
    for (var index = 0; index < tokens.length; index++) {
      expect(jsonDecode(authCalls[index].body)['gotrue_meta_security']['captcha_token'], tokens[index]);
    }
    await w.onboarding.signInWithEmail(email: 'fixture@example.invalid', password: 'synthetic');
    expect(jsonDecode(w.calls.last.body)['gotrue_meta_security']['captcha_token'], isNull);
  });
  test('different repository instances reject overlapping SDK writes',() async {
    final delayed = Completer<http.Response>();
    w.respond = (_) => delayed.future;
    final pending = w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    await expectLater(w.legacy.signIn(email:'other@example.invalid',password:'synthetic'),throwsStateError);
    await expectLater(SecureOnboardingRepository.forClient(w.client).registerAdmin(phone:'09012345678',password:'synthetic'),throwsStateError);
    await w.sent(1);
    expect(w.calls,hasLength(1));
    delayed.complete(Wire.json(session()));
    await pending;
  });
  test('logout intent supersedes delayed login, blocks writes and coalesces logout',() async {
    final delayed = Completer<http.Response>();
    final logoutReply = Completer<http.Response>();
    final logoutStarted = Completer<void>();
    w.respond = (request) {
      if(request.url.path.endsWith('/logout')) { logoutStarted.complete(); return logoutReply.future; }
      return delayed.future;
    };
    var loginExposed = false;
    final pending = w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic').then((_) { loginExposed = true; });
    final rejected = expectLater(pending,throwsStateError);
    await w.sent(1);
    final logout = w.auth.signOut();
    expect(w.auth.signOut(),same(logout));
    await expectLater(w.onboarding.signInWithPhone(phone:'09012345678',password:'synthetic'),throwsStateError);
    delayed.complete(Wire.json(session()));
    await rejected;
    await logoutStarted.future;
    expect(loginExposed,false);
    expect(w.client.auth.currentSession,isNull);
    await expectLater(w.auth.updateUser(UserAttributes(data:{'test':true})),throwsStateError);
    logoutReply.complete(http.Response('',204));
    await logout;
    expect(w.calls.where((r)=>r.url.path.endsWith('/logout')),hasLength(1));
    expect(w.calls.last.url.queryParameters['scope'],'local');
  });
  test('logout after failed login drains ownership and permits later login',() async {
    final delayed = Completer<http.Response>();
    w.respond = (_) => delayed.future;
    final pending = w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    final rejected = expectLater(pending,throwsA(isA<AuthException>()));
    await w.sent(1);
    final logout = w.auth.signOut();
    delayed.complete(http.Response('{"message":"denied","error":"invalid_grant"}',400,headers:{'content-type':'application/json'}));
    await rejected; await logout;
    w.respond = (_) async => Wire.json(session());
    await w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    expect(w.client.auth.currentUser?.id,actor);
  });
  test('context update cannot be queued behind interactive login',() async {
    await w.seed(); final delayed = Completer<http.Response>();
    w.respond = (_) => delayed.future;
    final pending = w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    await w.sent(1);
    await expectLater(w.onboarding.updatePrimaryPassword('synthetic-new-password'),throwsStateError);
    expect(w.calls.where((r)=>r.method=='PUT'),isEmpty);
    delayed.complete(Wire.json(session(sessionId:nextSid))); await pending;
  });
  test('raw SDK ABA interference rejects pending app result without rollback',() async {
    await w.seed(); final delayed = Completer<http.Response>();
    w.respond = (_) => delayed.future;
    final pending = w.onboarding.updatePrimaryPassword('synthetic-new-password');
    final rejected = expectLater(pending,throwsStateError);
    await w.sent(1);
    await w.seed(sessionId:nextSid); await w.seed();
    delayed.complete(Wire.json(user()));
    await rejected;
    expect(w.client.auth.currentSession?.refreshToken,'synthetic-$sid');
    expect(w.calls,hasLength(1)); // No compensating login/setSession/logout.
  });
  test('same SID actual SDK refresh while context update is pending remains compatible',() async {
    await w.seed(); final delayed = Completer<http.Response>();
    w.respond = (request) => request.method == 'PUT'
      ? delayed.future : Future.value(Wire.json(session(generation:2)));
    final pending = w.onboarding.updatePrimaryPassword('synthetic-new-password');
    await w.sent(1);
    await w.client.auth.refreshSession();
    delayed.complete(Wire.json(user())); await pending;
    expect(w.client.auth.currentUser?.id,actor);
    expect(w.calls,hasLength(2));
  });
  test('onboarding signup without session and SMS verify preserve actual flow',() async {
    w.respond = (request) async => request.url.path.endsWith('/signup')
      ? Wire.json({'user':user()}) : Wire.json(session());
    expect(await w.onboarding.registerAdmin(phone:'09012345678',password:'synthetic'),false);
    await w.onboarding.verifySmsCode(phone:'09012345678',code:'123456');
    expect(w.client.auth.currentUser?.id,actor);
    expect(jsonDecode(w.calls.first.body)['data'],{'sko_registration_type':'admin'});
    expect(jsonDecode(w.calls.last.body)['type'],'sms');
  });
  test('phone change verifies only same account, allows server session rotation',() async {
    await w.seed(); w.respond = (_) async => Wire.json(session(sessionId:nextSid));
    await w.auth.verifyPhoneChange(phone:'+819012345678',token:'123456');
    expect(w.client.auth.currentSession?.refreshToken,'synthetic-$nextSid');
  });
  test('phone change foreign account response never exposes success',() async {
    await w.seed(); w.respond = (_) async => Wire.json(session(uid:other,sessionId:nextSid));
    await expectLater(w.auth.verifyPhoneChange(phone:'+819012345678',token:'123456'),throwsStateError);
    expect(w.calls,hasLength(1));
  });
  test('legacy membership response is rejected after same-user session replacement',() async {
    final membership = Completer<http.Response>();
    final started = Completer<void>();
    w.respond = (request) async {
      if(request.url.path.endsWith('/company_members')) { started.complete(); return membership.future; }
      return Wire.json(session());
    };
    final pending = w.legacy.signIn(email:'fixture@example.invalid',password:'synthetic');
    final rejected = expectLater(pending,throwsStateError);
    await started.future; await w.seed(sessionId:nextSid);
    membership.complete(Wire.json([{'company_id':other,'role':'viewer'}]));
    await rejected;
    expect(w.calls.last.headers['authorization'],'Bearer ${session()['access_token']}');
  });
  test('missing or malformed context session stops before SDK network',() async {
    await expectLater(w.auth.updateUser(UserAttributes(data:{'test':true})),throwsStateError);
    await w.client.auth.setInitialSession(jsonEncode({...session(),'access_token':'malformed'}));
    await expectLater(w.auth.updateUser(UserAttributes(data:{'test':true})),throwsFormatException);
    expect(w.calls,isEmpty);
  });
  test('cached initial null event does not reject legitimate first login',() async {
    await w.client.auth.signOut();
    await Future<void>.delayed(Duration.zero);
    await w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    expect(w.client.auth.currentUser?.id,actor);
  });
  test('cached old signedIn permits a deliberate new SID password login',() async {
    await w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    w.respond = (_) async => Wire.json(session(sessionId:nextSid));
    await w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    expect(w.client.auth.currentSession?.refreshToken,'synthetic-$nextSid');
  });
  test('same SID fresh external login during context update rejects app result',() async {
    await w.seed(); final delayed = Completer<http.Response>();
    w.respond = (request) => request.method == 'PUT'
      ? delayed.future : Future.value(Wire.json(session(generation:2)));
    final pending = w.onboarding.updatePrimaryPassword('synthetic-new-password');
    final rejected = expectLater(pending,throwsStateError);
    await w.sent(1);
    await w.client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic');
    delayed.complete(Wire.json(user()));
    await rejected;
    expect(w.calls,hasLength(2));
  });
  test('logout before credential dispatch invalidates operation without sending password',() async {
    final pending = w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    final rejected = expectLater(pending,throwsStateError);
    final logout = w.auth.signOut();
    await rejected; await logout;
    expect(w.calls,isEmpty);
  });
  test('actual profile writes share lease and preserve normalized phone OTP flow',() async {
    await w.seed();
    final profile = ProfileRepository.forClient(w.client);
    expect(await profile.requestPhoneChange('09012345678'),'+819012345678');
    await profile.verifyPhoneChange(phone:'09012345678',code:' 123456 ');
    expect(jsonDecode(w.calls.first.body)['phone'],'+819012345678');
    expect(jsonDecode(w.calls.last.body)['type'],'phone_change');
    expect(jsonDecode(w.calls.last.body)['token'],'123456');
  });

  test('logout intent wins through SDK result and subscription finalization',() async {
    for (var hops = 0; hops < 12; hops++) {
      final fixture = Wire();
      try {
        final delayed = Completer<http.Response>();
        fixture.respond = (request) => request.url.path.endsWith('/logout')
          ? Future.value(http.Response('',204)) : delayed.future;
        var requested = false;
        var exposedAfterLogout = false;
        final pending = fixture.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic')
          .then((_) { exposedAfterLogout = requested; }, onError:(Object error) {
            expect(error,isA<StateError>());
          });
        await fixture.sent(1);
        Future<void> requestLogout() async {
          for(var i = 0; i < hops; i++) { await Future<void>.value(); }
          requested = true;
          await fixture.auth.signOut();
        }
        delayed.complete(Wire.json(session()));
        final logout = requestLogout();
        await pending; await logout;
        expect(exposedAfterLogout,false,reason:'logout at microtask boundary $hops');
        expect(fixture.client.auth.currentSession,isNull);
      } finally { await fixture.client.dispose(); }
    }
  });

  test('session inspection reserves existing repository writes and external admission',() async {
    await w.seed();
    final inspection = await w.auth.inspectCurrentSession();
    expect(inspection.isCurrent,isTrue);
    await expectLater(w.legacy.signIn(email:'other@example.invalid',password:'synthetic'),throwsStateError);
    await expectLater(w.auth.updateUser(UserAttributes(data:{'test':true})),throwsStateError);
    expect(await w.auth.externalFlowAdmission(),isNull);
    expect(w.calls,isEmpty);
    inspection.release();
    expect(inspection.isCurrent,isFalse);
    await w.legacy.signIn(email:'fixture@example.invalid',password:'synthetic');
    expect(w.calls.where((r)=>r.method=='POST' && r.url.path.endsWith('/token')),hasLength(1));
    expect(w.calls.where((r)=>r.method=='GET' && r.url.path.endsWith('/company_members')),hasLength(1));
    expect(w.calls,hasLength(2));
  });
  test('released inspection cannot release a newer owner',() async {
    await w.seed();
    final first = await w.auth.inspectCurrentSession();
    first.release();
    final second = await w.auth.inspectCurrentSession();
    first.release();
    expect(second.isCurrent,isTrue);
    await expectLater(w.auth.inspectCurrentSession(),throwsStateError);
    second.release();
  });
  test('logout cancels inspection synchronously without waiting for its reader',() async {
    await w.seed();
    final inspection = await w.auth.inspectCurrentSession();
    final logout = w.auth.signOut();
    expect(inspection.isCurrent,isFalse);
    await inspection.invalidated;
    await logout;
    expect(w.client.auth.currentSession,isNull);
    expect(w.calls.where((r)=>r.url.path.endsWith('/logout')),hasLength(1));
  });
  test('raw SDK A to B to A history permanently retires inspection',() async {
    await w.seed();
    final inspection = await w.auth.inspectCurrentSession();
    await w.seed(uid:other,sessionId:nextSid);
    await w.seed();
    await inspection.invalidated;
    expect(inspection.isCurrent,isFalse);
    expect(w.calls,isEmpty);
  });
  test('silent same UID restore is rejected even when token bytes are unchanged',() async {
    await w.seed();
    final inspection = await w.auth.inspectCurrentSession();
    await w.client.auth.recoverSession(jsonEncode(session()));
    expect(inspection.isCurrent,isFalse);
    await inspection.invalidated;
    expect(w.calls,isEmpty);
  });

}
