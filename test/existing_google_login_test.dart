import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/existing_google_login.dart';
import 'package:sk_works/features/auth/secure_onboarding_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const id = '20000000-0000-0000-0000-000000000001';
Session fixtureSession() {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return Session.fromJson({
    'access_token': '${part({'alg':'HS256'})}.${part({'sub':id,'role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic',
    'refresh_token':'synthetic', 'token_type':'bearer', 'expires_in':3600,
    'user':{'id':id,'aud':'authenticated','created_at':'2026-10-16T00:00:00Z','app_metadata':{'provider':'google'},'user_metadata':<String,dynamic>{}},
  })!;
}
class FakeGoogle extends ExistingGoogleLogin {
  FakeGoogle(super.client);
  final events = StreamController<AuthState>.broadcast(sync:true);
  Session? session;
  int launches=0, reads=0;
  bool launchResult=true, membership=true;
  Completer<bool>? read;
  @override Session? get currentSession => session;
  @override Stream<AuthState> get changes => events.stream;
  @override Future<bool> launch() async { launches++; return launchResult; }
  @override Future<bool> hasExistingMembership(Session s) async { reads++; if (read != null) return read!.future; return membership; }
  void signedIn() { session=fixtureSession(); events.add(AuthState(AuthChangeEvent.signedIn, session)); }
}
void main() {
  late SupabaseClient client;
  setUpAll(() { client=SupabaseClient('https://google-login-fixture.invalid','public_fixture', authOptions:const AuthClientOptions(autoRefreshToken:false), httpClient:MockClient((r) async => throw StateError('No live authentication: ${r.url.host}'))); });
  tearDownAll(() async { await client.dispose(); });
  Future<void> show(WidgetTester t, FakeGoogle g, VoidCallback done) async {
    await t.binding.setSurfaceSize(const Size(900,1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home:SecureAuthPage(googleLogin:g,onAuthenticated:done)));
    await t.pumpAndSettle();
  }
  testWidgets('launch is not success; existing SDK session and membership finish once', (t) async {
    final g=FakeGoogle(client); var done=0;
    await show(t,g,()=>done++);
    await t.tap(find.text('登録済みのGoogleでログイン')); await t.pumpAndSettle();
    expect(g.launches,1); expect(done,0); expect(g.reads,0);
    g.signedIn(); await t.pumpAndSettle();
    expect(done,1); expect(g.reads,1);
    g.signedIn(); await t.pumpAndSettle(); expect(done,1);
    await g.events.close();
  });
  testWidgets('cancel and disposed page ignore late callback; phone and registration remain', (t) async {
    final g=FakeGoogle(client); var done=0;
    await show(t,g,()=>done++);
    expect(find.text('管理者として初めて登録する'),findsOneWidget);
    expect(find.text('従業員登録QRでログイン'),findsOneWidget);
    await t.tap(find.text('登録済みのGoogleでログイン')); await t.pumpAndSettle();
    await t.tap(find.text('Googleログインを中止')); await t.pumpAndSettle();
    g.signedIn(); await t.pumpAndSettle(); expect(done,0); expect(g.reads,0);
    await t.pumpWidget(const SizedBox()); g.signedIn(); await t.pump(); expect(done,0);
    await g.events.close();
  });
  testWidgets('background result waits for resume and actor change rejects late membership', (t) async {
    final g=FakeGoogle(client); var done=0;
    await show(t,g,()=>done++);
    await t.tap(find.text('登録済みのGoogleでログイン')); await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    g.signedIn(); await t.pump(); expect(g.reads,0); expect(done,0);
    g.read=Completer<bool>();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pump();
    expect(g.reads,1); g.session=null; g.read!.complete(true); await t.pumpAndSettle(); expect(done,0);
    await g.events.close();
  });
  testWidgets('unknown membership never completes', (t) async {
    final g=FakeGoogle(client)..membership=false; var done=0;
    await show(t,g,()=>done++); await t.tap(find.text('登録済みのGoogleでログイン')); await t.pumpAndSettle();
    g.signedIn(); await t.pumpAndSettle(); expect(done,0);
    expect(find.textContaining('既存の会社登録を確認できません'),findsOneWidget);
    await g.events.close();
  });
  testWidgets('failed browser launch never authenticates', (t) async {
    final g=FakeGoogle(client)..launchResult=false; var done=0;
    await show(t,g,()=>done++);
    await t.tap(find.text('登録済みのGoogleでログイン')); await t.pumpAndSettle();
    expect(done,0); expect(g.reads,0);
    expect(find.text('Googleログインを開けませんでした。'),findsOneWidget);
    await g.events.close();
  });
  test('fixed session bearer, user filter, callback constant and no authentication writes', () async {
    final calls=<http.Request>[]; final session=fixtureSession();
    final c=SupabaseClient('https://google-login-fixture.invalid','public_fixture',authOptions:const AuthClientOptions(autoRefreshToken:false),httpClient:MockClient((r) async {
      calls.add(r);
      if(r.url.path=='/auth/v1/token') return http.Response(jsonEncode(session.toJson()),200,headers:{'content-type':'application/json'},request:r);
      if(r.url.path=='/rest/v1/company_members') return http.Response('[{"company_id":"synthetic-company"}]',200,headers:{'content-type':'application/json'},request:r);
      throw StateError('Unexpected fixture request');
    }));
    await c.auth.signInWithPassword(phone:'+819012345678',password:'synthetic');
    final g=ExistingGoogleLogin(c);
    expect(await g.hasExistingMembership(c.auth.currentSession!),true);
    final r=calls.last; expect(r.headers['Authorization'],'Bearer ${session.accessToken}');
    expect(r.url.queryParameters['user_id'],'eq.$id'); expect(r.method,'GET');
    expect(ExistingGoogleLogin.nativeRedirect,'com.skworks.sko://login-callback/');
    expect(calls.where((r)=>r.url.path=='/auth/v1/signup'||r.url.path=='/auth/v1/user'),isEmpty);
    await c.dispose();
  });
}
