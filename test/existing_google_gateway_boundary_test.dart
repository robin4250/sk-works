import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
// Test-only native handoff spy; no browser/provider is contacted.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:sk_works/features/auth/existing_google_login.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

class BrowserSpy extends UrlLauncherPlatform {
  final urls=<Uri>[];
  @override get linkDelegate => null;
  @override Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
  @override Future<bool> launchUrl(String url,LaunchOptions options) async { urls.add(Uri.parse(url)); return true; }
}
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
      await w.seed(); final reply=Completer<http.Response>(); w.respond=(_)=>reply.future;
      final logout=w.auth.signOut(); final rejected=failed?expectLater(logout,throwsA(isA<AuthException>())):null;
      await w.sent(1);
      if(failed) { reply.complete(http.Response('{"message":"unavailable"}',503,headers:{'content-type':'application/json'})); await rejected; }
      final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
      UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
      Object? error;
      try { try { await ExistingGoogleLogin(w.client).launch(); } catch(e) { error=e; } }
      finally {
        UrlLauncherPlatform.instance=oldPlatform;
        if(!failed) { reply.complete(http.Response('',204)); await logout; }
      }
      expect(error,isA<StateError>()); expect(spy.urls,isEmpty);
    });
  }
  test('ordinary iOS native Google handoff retains provider redirect and account selector',() async {
    final oldPlatform=UrlLauncherPlatform.instance; final spy=BrowserSpy();
    UrlLauncherPlatform.instance=spy; debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
    try {
      expect(await ExistingGoogleLogin(w.client).launch(),true);
      expect(spy.urls,hasLength(1));
      expect(spy.urls.single.queryParameters['provider'],'google');
      expect(spy.urls.single.queryParameters['redirect_to'],ExistingGoogleLogin.nativeRedirect);
      expect(spy.urls.single.queryParameters['prompt'],'select_account');
      expect(w.calls,isEmpty); expect(w.client.auth.currentSession,isNull);
    } finally { UrlLauncherPlatform.instance=oldPlatform; }
  });
}
