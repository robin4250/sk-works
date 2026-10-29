import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Test-only native handoff spy; no browser/provider is contacted.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:sk_works/features/auth/existing_google_login.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

class BrowserSpy extends UrlLauncherPlatform {
  final urls=<Uri>[];
  final options=<LaunchOptions>[];
  Completer<bool>? gate;
  @override get linkDelegate => null;
  @override Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
  @override Future<bool> launchUrl(String url,LaunchOptions options) async { urls.add(Uri.parse(url)); this.options.add(options); return gate==null?true:await gate!.future; }
}
class MemoryPkce extends GotrueAsyncStorage {
  final _values=<String,String>{};
  Completer<void>? writeGate;
  int writes=0;
  @override Future<String?> getItem({required String key}) async => _values[key];
  @override Future<void> setItem({required String key,required String value}) async { writes++; await writeGate?.future; _values[key]=value; }
  @override Future<void> removeItem({required String key}) async { _values.remove(key); }
}
SupabaseClient nativeClient(fixture.Wire w,{MemoryPkce? pkce}) => SupabaseClient('https://native-google-fixture.invalid','public-fixture',
  authOptions:AuthClientOptions(autoRefreshToken:false,pkceAsyncStorage:pkce??MemoryPkce()),
  httpClient:MockClient((request) async { w.calls.add(request); return w.respond(request); }));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Wire w;
  setUp(() { w=fixture.Wire(); });
  tearDown(() async { debugDefaultTargetPlatformOverride=null; await w.client.dispose(); });
  test('membership rejects actual SDK A to B to A history despite identical final bearer',() async {
    await w.seed(); final original=w.client.auth.currentSession!;
    final reply=Completer<http.Response>(); w.respond=(_)=>reply.future;
    final read=ExistingGoogleLogin(w.client).hasExistingMembership(original);
    await w.sent(1); await w.seed(sessionId:fixture.nextSid); await w.seed();
    expect(w.client.auth.currentSession!.accessToken,original.accessToken);
    reply.complete(fixture.Wire.json([{'company_id':fixture.other}]));
    expect(await read,false);
  });
  test('membership rejects fresh same-SID SDK signedIn during delayed read',() async {
    await w.seed(); final original=w.client.auth.currentSession!;
    final reply=Completer<http.Response>();
    w.respond=(request)=>request.url.path.endsWith('/token') ? Future.value(fixture.Wire.json(fixture.session())) : reply.future;
    final read=ExistingGoogleLogin(w.client).hasExistingMembership(original);
    await w.sent(1); await w.client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic');
    reply.complete(fixture.Wire.json([{'company_id':fixture.other}]));
    expect(await read,false);
  });
  test('membership result is denied immediately by logout intent while SDK write stalls',() async {
    await w.seed(); final original=w.client.auth.currentSession!;
    final membership=Completer<http.Response>(), login=Completer<http.Response>();
    w.respond=(request) => request.url.path.endsWith('/token') ? login.future
      : request.url.path.endsWith('/logout') ? Future.value(http.Response('',204)) : membership.future;
    final read=ExistingGoogleLogin(w.client).hasExistingMembership(original);
    await w.sent(1);
    final pending=w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
    final rejected=expectLater(pending,throwsStateError); await w.sent(2);
    final logout=w.auth.signOut();
    membership.complete(fixture.Wire.json([{'company_id':fixture.other}])); final allowed=await read;
    login.complete(fixture.Wire.json(fixture.session())); await rejected; await logout;
    expect(allowed,false);
  });
  test('ordinary unchanged actual SDK membership remains accepted',() async {
    await w.seed();
    expect(await ExistingGoogleLogin(w.client).hasExistingMembership(w.client.auth.currentSession!),true);
  });
  for(final failed in [false,true]) {
    test('native OAuth handoff is denied for ${failed?'failed':'pending'} logout quarantine',() async {
      final c=nativeClient(w); await c.auth.setInitialSession(jsonEncode(fixture.session()));
      final reply=Completer<http.Response>(); w.respond=(_)=>reply.future;
      final logout=AppAuthMutationGateway.forClient(c).signOut(); final rejected=failed?expectLater(logout,throwsA(isA<AuthException>())):null;
      await w.sent(1);
      if(failed) { reply.complete(http.Response('{"message":"unavailable"}',503,headers:{'content-type':'application/json'})); await rejected; }
      final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
      UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
      Object? error;
      try { try { await ExistingGoogleLogin(c).launch(); } catch(e) { error=e; } }
      finally {
        UrlLauncherPlatform.instance=oldPlatform;
        if(!failed) { reply.complete(http.Response('',204)); await logout; }
        await c.dispose();
      }
      expect(spy.urls.length,0); expect(error,isA<StateError>());
    });
  }
  test('ordinary iOS native Google handoff retains provider redirect and account selector',() async {
    final c=nativeClient(w);
    final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
    UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    try {
      expect(await ExistingGoogleLogin(c).launch(),true);
      expect(spy.urls,hasLength(1));
      expect(spy.urls.single.queryParameters['provider'],'google');
      expect(spy.urls.single.queryParameters['redirect_to'],ExistingGoogleLogin.nativeRedirect);
      expect(spy.urls.single.queryParameters['prompt'],'select_account');
      expect(spy.urls.single.queryParameters['code_challenge_method'],'s256');
      expect(spy.options.single.mode,PreferredLaunchMode.platformDefault);
      expect(spy.options.single.webOnlyWindowName,'_self');
      expect(w.calls,isEmpty); expect(c.auth.currentSession,isNull);
    } finally { UrlLauncherPlatform.instance=oldPlatform; await c.dispose(); }
  });
  test('cached exact SDK session replay admits ordinary external flow',() async {
    final c=nativeClient(w);
    try {
      await c.auth.setInitialSession(jsonEncode(fixture.session()));
      final owner=AppAuthMutationGateway.forClient(c);
      expect(await owner.externalFlowAdmission(),isNotNull);
    } finally { await c.dispose(); }
  });
  test('first live SDK boundary during replay drain is not accepted as baseline',() async {
    final c=nativeClient(w);
    try {
      await c.auth.setInitialSession(jsonEncode(fixture.session()));
      final owner=AppAuthMutationGateway.forClient(c);
      final admission=owner.externalFlowAdmission();
      await c.auth.setInitialSession(jsonEncode(fixture.session()));
      expect(await admission,isNull);
      expect(await owner.externalFlowAdmission(),isNotNull);
    } finally { await c.dispose(); }
  });
  test('SDK stream error rejects pending membership and permanently closes external view',() async {
    await w.seed(); final reply=Completer<http.Response>(); w.respond=(_)=>reply.future;
    final read=ExistingGoogleLogin(w.client).hasExistingMembership(w.client.auth.currentSession!);
    await w.sent(1);
    await expectLater(w.client.auth.recoverSession('synthetic-invalid-json'),throwsFormatException);
    reply.complete(fixture.Wire.json([{'company_id':fixture.other}]));
    expect(await read,false);
    await w.seed();
    expect(await w.auth.externalFlowAdmission(),isNull);
    expect(w.calls,hasLength(1));
  });
  test('SDK disposal permanently closes external admission and observer cleanup',() async {
    final c=nativeClient(w); final owner=AppAuthMutationGateway.forClient(c);
    expect(await owner.externalFlowAdmission(),isNotNull);
    await c.dispose(); await Future<void>.value();
    expect(await owner.externalFlowAdmission(),isNull);
  });
  test('native OAuth handoff rejects concurrent app-owned password mutation',() async {
    final c=nativeClient(w); final owner=AppAuthMutationGateway.forClient(c);
    final reply=Completer<http.Response>(); w.respond=(_)=>reply.future;
    final pending=owner.signInWithPassword(email:'fixture@example.invalid',password:'synthetic'); await w.sent(1);
    final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
    UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    Object? error;
    try { try { await ExistingGoogleLogin(c).launch(); } catch(e) { error=e; } }
    finally {
      UrlLauncherPlatform.instance=oldPlatform; reply.complete(fixture.Wire.json(fixture.session()));
      await pending; await c.dispose();
    }
    expect(spy.urls.length,0); expect(error,isA<StateError>());
  });
  test('logout after native handoff revokes launch result but cannot recall browser',() async {
    final c=nativeClient(w); final oldPlatform=UrlLauncherPlatform.instance;
    final spy=BrowserSpy()..gate=Completer<bool>();
    UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    try {
      final launch=ExistingGoogleLogin(c).launch(); final rejected=expectLater(launch,throwsStateError);
      for(var i=0;i<30 && spy.urls.isEmpty;i++) { await Future<void>.value(); }
      expect(spy.urls.length,1);
      await AppAuthMutationGateway.forClient(c).signOut();
      spy.gate!.complete(true); await rejected;
      expect(spy.urls.length,1); expect(c.auth.currentSession,isNull);
    } finally { UrlLauncherPlatform.instance=oldPlatform; await c.dispose(); }
  });

  test('logout between admission completion and launch continuation prevents handoff',() async {
    final c=nativeClient(w); final owner=AppAuthMutationGateway.forClient(c);
    expect(await owner.externalFlowAdmission(),isNotNull);
    final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
    UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    try {
      final launch=ExistingGoogleLogin(c).launch(); final rejected=expectLater(launch,throwsStateError);
      final logoutDone=Completer<void>();
      scheduleMicrotask(() { owner.signOut().then((_)=>logoutDone.complete(),onError:logoutDone.completeError); });
      await logoutDone.future; await rejected;
      expect(spy.urls.length,0);
    } finally { UrlLauncherPlatform.instance=oldPlatform; await c.dispose(); }
  });
  test('successful actual SDK refresh permits subsequent new external admission',() async {
    await w.seed(); await w.client.auth.refreshSession(); await Future<void>.value();
    expect(await w.auth.externalFlowAdmission(),isNotNull);
    expect(await ExistingGoogleLogin(w.client).hasExistingMembership(w.client.auth.currentSession!),true);
  });

  test('logout during actual PKCE storage await prevents native handoff',() async {
    final pkce=MemoryPkce()..writeGate=Completer<void>(); final c=nativeClient(w,pkce:pkce);
    final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
    UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    try {
      final launch=ExistingGoogleLogin(c).launch(); final rejected=expectLater(launch,throwsStateError);
      for(var i=0;i<40 && pkce.writes==0;i++) { await Future<void>.value(); }
      expect(pkce.writes,1); expect(spy.urls.length,0);
      await AppAuthMutationGateway.forClient(c).signOut();
      pkce.writeGate!.complete(); await rejected;
      expect(spy.urls.length,0); expect(c.auth.currentSession,isNull);
    } finally { UrlLauncherPlatform.instance=oldPlatform; await c.dispose(); }
  });

}
