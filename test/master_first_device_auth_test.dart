import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/secure_onboarding_repository.dart';
import 'package:sk_works/features/settings/master_device_repository.dart';
import 'package:sk_works/features/settings/master_protected_page.dart';

const _actor = '80000000-0000-0000-0000-000000000001';
const _other = '80000000-0000-0000-0000-000000000002';
Map<String,dynamic> _session(String actor) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {'access_token':'${part({'alg':'HS256'})}.${part({'sub':actor,'role':'authenticated','session_id':'80000000-0000-0000-0000-000000000003','exp':DateTime.now().millisecondsSinceEpoch ~/ 1000+3600})}.synthetic',
    'refresh_token':'synthetic-$actor','token_type':'bearer','expires_in':3600,
    'user':{'id':actor,'aud':'authenticated','created_at':'2026-10-16T00:00:00Z','app_metadata':{'providers':['google']},'user_metadata':<String,dynamic>{}}};
}
class _Fixture {
  late SupabaseClient client;
  final requests = <http.Request>[];
  final passwords = <String>[];
  final native = <String>[];
  bool trusted = false, master = true, face = true, allowBootstrap = true;
  int bootstraps = 0;
  Completer<bool>? faceWait;
  Completer<void>? verifyWait;
  String? expectedBearer;
  static Future<_Fixture> create() async {
    final f = _Fixture();
    f.client = SupabaseClient('https://master-first-device-fixture.invalid','public_fixture',
      headers: {'Authorization':'Bearer synthetic-default-header'},
      authOptions: AuthClientOptions(autoRefreshToken:false),
      httpClient: MockClient((r) async {
        expect(r.url.host,'master-first-device-fixture.invalid');
        f.requests.add(r);
        expect(r.headers['Authorization'],f.expectedBearer);
        final operation = r.url.path.split('/').last;
        dynamic result;
        switch(operation) {
          case 'current_master_admin_status': result={'is_master_admin':f.master};
          case 'current_master_device_status': result={'is_master_admin':f.master,'trusted':f.master && f.trusted,'can_bootstrap':f.master && !f.trusted && f.allowBootstrap};
          case 'secondary_password_configured': result=true;
          case 'verify_secondary_password':
            final password=(jsonDecode(r.body) as Map)['p_password'] as String;
            f.passwords.add(password);
            if(f.verifyWait!=null) await f.verifyWait!.future;
            result=password=='existing-secondary-password';
          case 'bootstrap_first_master_device':
            expect(f.master,isTrue); expect(f.allowBootstrap,isTrue); expect(f.trusted,isFalse);
            final body=jsonDecode(r.body) as Map;
            expect((body['p_device_key'] as String).length,greaterThanOrEqualTo(32));
            expect(body.keys.toSet(),{'p_device_key','p_device_name','p_device_type','p_platform'});
            f.bootstraps++; f.trusted=true; result={'trusted':true};
          default: throw StateError('Unexpected synthetic request');
        }
        return http.Response(jsonEncode(result),200,headers:{'content-type':'application/json'},request:r);
      }));
    await f.client.auth.setInitialSession(jsonEncode(_session(_actor)));
    f.expectedBearer='Bearer ${f.client.auth.currentSession!.accessToken}';
    return f;
  }
}
Future<void> _show(WidgetTester t,_Fixture f) async {
  debugDefaultTargetPlatformOverride=TargetPlatform.iOS;
  SharedPreferences.setMockInitialValues({});
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  const channel=MethodChannel('plugins.flutter.io/local_auth');
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
    f.native.add(call.method);
    switch(call.method) {
      case 'getAvailableBiometrics': return ['face'];
      case 'deviceSupportsBiometrics':
      case 'isDeviceSupported': return true;
      case 'authenticate': return f.faceWait==null ? f.face : f.faceWait!.future;
      case 'stopAuthentication': return true;
      default: throw StateError('Unexpected native fixture method');
    }
  });
  addTearDown(() { t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,null); debugDefaultTargetPlatformOverride=null; });
  await t.binding.setSurfaceSize(const Size(900,1400));
  addTearDown(()=>t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home:MasterProtectedPage(title:'Master fixture',legacyDeviceRepository:MasterDeviceRepository.forTesting(f.client),legacyAuthRepository:SecureOnboardingRepository.forClient(f.client),legacySessionToken:()=>f.client.auth.currentSession?.accessToken,legacyChanges:f.client.auth.onAuthStateChange.map((_) {}),child:const Scaffold(body:Text('LEGACY-AND-MASTER-CONTENT')))));
  await t.pumpAndSettle();
}
Future<void> _start(WidgetTester t) async {
  await t.enterText(find.byType(TextField),'existing-secondary-password');
  await t.tap(find.text('本人確認してこの端末を登録')); await t.pumpAndSettle();
}
Future<void> _close(WidgetTester t,_Fixture f) async {
  await t.pumpWidget(const SizedBox()); await t.pump(); await t.runAsync(()=>f.client.dispose());
}
void main() {
  testWidgets('first device zero with existing secondary: Face inactive cannot erase the submitted secret; AND policy retained', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; f.faceWait=Completer<bool>(); await _show(t,f);
    expect(find.text('本人確認してこの端末を登録'),findsOneWidget);
    await _start(t); expect(f.passwords,isEmpty); expect(f.bootstraps,0);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await t.pump();
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text,isEmpty);
    f.faceWait!.complete(true); await t.pumpAndSettle();
    expect(f.passwords,isEmpty); expect(f.bootstraps,0);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pumpAndSettle();
    expect(f.passwords,['existing-secondary-password']); expect(f.bootstraps,1);
    expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsOneWidget);
    expect(f.client.headers['Authorization'],'Bearer synthetic-default-header');
    expect(f.requests.any((r)=>r.url.path.contains('/signup')||r.url.path.contains('set_secondary')||r.url.path.contains('/auth/v1/user')),isFalse);
    await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('Face cancel registers no device and does not submit secondary', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; f.face=false; await _show(t,f); await _start(t);
    expect(f.passwords,isEmpty); expect(f.bootstraps,0); expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsNothing); await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('wrong secondary never uses Face alone as OR and registers no device', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; await _show(t,f);
    await t.enterText(find.byType(TextField),'wrong-secondary'); await t.tap(find.text('本人確認してこの端末を登録')); await t.pumpAndSettle();
    expect(f.native.where((m)=>m=='authenticate').length,1); expect(f.passwords,['wrong-secondary']); expect(f.bootstraps,0);
    expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsNothing); await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('real background rejects late Face and does not register first device', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; f.faceWait=Completer<bool>(); await _show(t,f); await _start(t);
    for(final state in [AppLifecycleState.inactive,AppLifecycleState.hidden,AppLifecycleState.paused,AppLifecycleState.hidden,AppLifecycleState.inactive,AppLifecycleState.resumed]) { t.binding.handleAppLifecycleStateChanged(state); }
    f.faceWait!.complete(true); await t.pumpAndSettle();
    expect(f.passwords,isEmpty); expect(f.bootstraps,0); expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsNothing); await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('actor changes during native Face cannot verify or register for the other actor', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; f.faceWait=Completer<bool>(); await _show(t,f); await _start(t);
    await t.runAsync(()=>f.client.auth.setInitialSession(jsonEncode(_session(_other)))); await t.pump();
    f.faceWait!.complete(true); await t.pumpAndSettle();
    expect(f.passwords,isEmpty); expect(f.bootstraps,0); expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsNothing); await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('server role revoked during password verification prevents bootstrap', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; f.verifyWait=Completer<void>(); await _show(t,f); await _start(t);
    expect(f.passwords,['existing-secondary-password']); f.master=false; f.verifyWait!.complete(); await t.pumpAndSettle();
    expect(f.bootstraps,0); expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsNothing); await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
  testWidgets('server bootstrap eligibility removed during verification prevents enrollment', (t) async {
    final f=(await t.runAsync(_Fixture.create))!; f.verifyWait=Completer<void>(); await _show(t,f); await _start(t);
    f.allowBootstrap=false; f.verifyWait!.complete(); await t.pumpAndSettle();
    expect(f.bootstraps,0); expect(find.text('LEGACY-AND-MASTER-CONTENT'),findsNothing); await _close(t,f);
  }, timeout: const Timeout(Duration(minutes: 1)));
}
