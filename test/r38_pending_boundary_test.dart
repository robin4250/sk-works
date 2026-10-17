import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';

const actorA = '20000000-0000-0000-0000-000000000001';
const actorB = '20000000-0000-0000-0000-000000000002';
Completer<bool>? pending;
Completer<bool>? nativePending;
bool configured = true;
Completer<bool>? pendingConfigured;
final requests = <http.Request>[];
String session(String actor, {int epoch = 0}) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value)));
  return jsonEncode({'access_token': '${part({'alg':'HS256'})}.${part({'sub':actor,'exp':4102444800,'fixture_epoch':epoch})}.synthetic',
    'refresh_token':'synthetic-only', 'token_type':'bearer', 'expires_in':3600,
    'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-17T00:00:00Z'}});
}
Future<void> settle(WidgetTester tester) async {
  for (var i=0;i<5;i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:10)));
    await tester.pump(const Duration(milliseconds:20));
  }
  await tester.pumpAndSettle();
}
Future<void> open(WidgetTester tester, {bool setup = false, bool loading = false}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.runAsync(() => Supabase.instance.client.auth.setInitialSession(session(actorA)));
  expect(SupabaseBackend.client.auth.currentUser?.id,actorA);
  await tester.pumpWidget(const MaterialApp(home: SecondaryProtectedPage(
    title:'synthetic protected',child:Text('private payload'))));
  if (loading) {await tester.pump();return;}
  await settle(tester);
  expect(find.text(setup ? '第2パスワードを設定' : '第2認証が必要です'),findsOneWidget,
    reason:tester.widgetList<Text>(find.byType(Text)).map((t)=>t.data).join('|'));
}
Future<void> begin(WidgetTester tester) async {
  pending=Completer<bool>();
  await tester.enterText(find.byType(TextField).first,'synthetic-secondary');
  await tester.tap(find.text('第2パスワードで開く'));
  await tester.pump();
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SKO_R38_FIXTURE')) {
    test('dedicated synthetic configuration required',(){},skip:'Use R38 workflow.');
    return;
  }
  setUpAll(() async {
    expect(SupabaseBackendConfig.url,'https://r38-fixture.invalid');
    expect(SupabaseBackendConfig.publishableKey,'public_fixture');
    SharedPreferences.setMockInitialValues({'sko_secondary_biometric_enabled_$actorA':true});
    await Supabase.initialize(url:SupabaseBackendConfig.url,publishableKey:SupabaseBackendConfig.publishableKey,
      debug:false,authOptions:const FlutterAuthClientOptions(autoRefreshToken:false,detectSessionInUri:false),
      httpClient:MockClient((request) async {
        expect(request.url.host,'r38-fixture.invalid');requests.add(request);
        if(request.url.path.endsWith('/secondary_password_configured')) return http.Response(jsonEncode(pendingConfigured == null ? configured : await pendingConfigured!.future),200,headers:{'content-type':'application/json'},request:request);
        if(request.url.path.endsWith('/set_secondary_password')) return http.Response('null',200,headers:{'content-type':'application/json'},request:request);
        if(request.url.path.endsWith('/verify_secondary_password')) {
          expect(jsonDecode(request.body),{'p_password':'synthetic-secondary'});
          return http.Response(jsonEncode(await pending!.future),200,headers:{'content-type':'application/json'},request:request);
        }
        throw StateError('Unexpected synthetic endpoint');
      }));
    await SupabaseBackend.initializeIfConfigured();
  });
  tearDownAll(() async {await Supabase.instance.dispose();});
  setUp(() {
    requests.clear();pending=null;nativePending=null;pendingConfigured=null;configured=true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),(call) async {
        if(call.method=='isDeviceSupported'||call.method=='deviceSupportsBiometrics')return true;
        if(call.method=='getAvailableBiometrics')return ['face'];
        if(call.method=='authenticate')return await nativePending!.future;
        throw StateError('No native authentication permitted in password fixture');
      });
  });
  tearDown(() {TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/local_auth'),null);});
  testWidgets('background rejects delayed password success; fresh foreground retry still works',(tester) async {
    await open(tester);await begin(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    pending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await settle(tester);
    expect(find.text('private payload'),findsNothing);
    await begin(tester);pending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('sko_secondary_biometric_enabled_$actorA'),true);
    expect(requests.where((r)=>r.url.path.endsWith('/verify_secondary_password')).length,2);
  });
  testWidgets('actor switch rejects delayed success without identity or password mutation',(tester) async {
    await open(tester);await begin(tester);
    await tester.runAsync(() => Supabase.instance.client.auth.setInitialSession(session(actorB)));
    pending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsNothing);
    expect(Supabase.instance.client.auth.currentUser!.id,actorB);
    expect(requests.every((r)=>r.url.path.endsWith('/secondary_password_configured')||r.url.path.endsWith('/verify_secondary_password')),true);
  });
  testWidgets('native inactive completion waits for resumed before revealing content',(tester) async {
    await open(tester);nativePending=Completer<bool>();
    await tester.tap(find.text('Face ID / Touch IDで開く'));await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    nativePending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await settle(tester);
    expect(find.text('private payload'),findsOneWidget);
  });
  testWidgets('old resumed completion cannot release busy state owned by a fresh retry',(tester) async {
    await open(tester);await begin(tester);final old=pending!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await settle(tester);
    await begin(tester);final fresh=pending!;
    old.complete(true);await settle(tester);
    expect(find.text('private payload'),findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,isNull);
    fresh.complete(true);await settle(tester);
    expect(find.text('private payload'),findsOneWidget);
  });
  testWidgets('native real background rejects delayed success after resume',(tester) async {
    await open(tester);nativePending=Completer<bool>();
    await tester.tap(find.text('Face ID / Touch IDで開く'));await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    nativePending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsNothing);
  });
  testWidgets('setup native callback after background never submits cleared password',(tester) async {
    configured=false;await open(tester,setup:true);nativePending=Completer<bool>();
    await tester.enterText(find.byType(TextField).at(0),'synthetic-new-secondary');
    await tester.enterText(find.byType(TextField).at(1),'synthetic-new-secondary');
    await tester.ensureVisible(find.byType(SwitchListTile));await tester.tap(find.byType(SwitchListTile));await tester.pump();
    await tester.ensureVisible(find.text('設定して開く'));await tester.tap(find.text('設定して開く'));await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    nativePending!.complete(true);await settle(tester);
    expect(requests.where((r)=>r.url.path.endsWith('/set_secondary_password')),isEmpty);
    expect(find.text('private payload'),findsNothing);
  });
  testWidgets('setup native inactive waits then submits captured password once on resume',(tester) async {
    configured=false;await open(tester,setup:true);nativePending=Completer<bool>();
    await tester.enterText(find.byType(TextField).at(0),'synthetic-new-secondary');
    await tester.enterText(find.byType(TextField).at(1),'synthetic-new-secondary');
    await tester.ensureVisible(find.byType(SwitchListTile));await tester.tap(find.byType(SwitchListTile));await tester.pump();
    await tester.ensureVisible(find.text('設定して開く'));await tester.tap(find.text('設定して開く'));await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    nativePending!.complete(true);await settle(tester);
    expect(requests.where((r)=>r.url.path.endsWith('/set_secondary_password')),isEmpty);
    expect(find.text('private payload'),findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await settle(tester);
    final saves=requests.where((r)=>r.url.path.endsWith('/set_secondary_password')).toList();
    expect(saves.length,1);
    expect(jsonDecode(saves.single.body),{'p_password':'synthetic-new-secondary'});
    expect(find.text('private payload'),findsOneWidget);
  });
  testWidgets('token refresh during verification rejects old proof and permits reload and retry',(tester) async {
    await open(tester);await begin(tester);
    await tester.runAsync(() => Supabase.instance.client.auth.setInitialSession(session(actorA,epoch:1)));
    pending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsNothing);
    await tester.tap(find.text('再読み込み'));await settle(tester);
    await begin(tester);pending!.complete(true);await settle(tester);
    expect(find.text('private payload'),findsOneWidget);
  });
  testWidgets('token refresh during initial status load does not leave an endless spinner',(tester) async {
    pendingConfigured=Completer<bool>();await open(tester,loading:true);
    await tester.runAsync(() async {await Future<void>.delayed(const Duration(milliseconds:20));});
    await tester.runAsync(() => Supabase.instance.client.auth.setInitialSession(session(actorA,epoch:2)));
    pendingConfigured!.complete(true);await settle(tester);pendingConfigured=null;
    expect(find.byType(CircularProgressIndicator),findsNothing);
    expect(find.text('private payload'),findsNothing);
    await tester.tap(find.text('再読み込み'));await settle(tester);
    expect(find.text('第2認証が必要です'),findsOneWidget);
  });
}
