import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/settings/master_protected_page.dart';

const _actor = '40000000-0000-0000-0000-000000000001';
class _Access implements MasterSecondaryAccess {
  @override String? actor = _actor;
  @override String? token = 'synthetic-token-A';
  bool master = true;
  bool trusted = true;
  bool canBootstrap = false;
  bool configuredValue = true;
  bool bioResult = true;
  bool passwordResult = true;
  int biometricCalls = 0;
  int bootstrapCalls = 0;
  int masterCalls = 0;
  final passwords = <String>[];
  Completer<bool>? biometricWait;
  Completer<bool>? passwordWait;
  Completer<bool>? configuredWait;
  @override Future<bool> isMaster() async { masterCalls++; return master; }
  @override Future<Map<String,dynamic>> status(String key) async => {'trusted': trusted, 'can_bootstrap': canBootstrap};
  @override Future<bool> configured() async => configuredWait == null ? configuredValue : configuredWait!.future;
  @override Future<bool> biometricAvailable() async => true;
  @override Future<bool> biometric() async { biometricCalls++; return biometricWait == null ? bioResult : biometricWait!.future; }
  @override Future<bool> verify(String password, String capturedToken) async { passwords.add(password); return passwordWait == null ? passwordResult : passwordWait!.future; }
  @override Future<void> bootstrap(String key, String name, String type, String platform, String capturedToken) async { bootstrapCalls++; trusted = true; canBootstrap = false; }
}
Future<void> _show(WidgetTester tester, _Access access, {bool opted = true, bool settle = true}) async {
  SharedPreferences.setMockInitialValues({'sko_master_device_key_$_actor': 'synthetic-device-key-longer-than-32-characters', 'sko_secondary_biometric_enabled_$_actor': opted});
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(home: MasterProtectedPage(title: 'Master test', access: access, child: const Scaffold(body: Text('MASTER-CONTENT')))));
  if (settle) { await tester.pumpAndSettle(); } else { for (var i = 0; i < 5; i++) { await tester.pump(); } }
}
Future<void> _password(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'existing-secondary');
  await tester.tap(find.text('第2パスワードで開く'));
  await tester.pumpAndSettle();
}
Future<void> _close(WidgetTester tester) async { await tester.pumpWidget(const SizedBox()); await tester.pump(); }
void main() {
  test('trusted normal entry is explicit secondary OR opted-in Face; bootstrap still AND', () {
    bool allowed({bool password = false, bool face = false, bool opted = true, bool bootstrap = false, bool master = true, bool trusted = true}) => MasterSecondaryEntryPolicy.allows(master: master, trusted: trusted, configured: true, passwordVerified: password, biometricVerified: face, biometricEnabled: opted, bootstrap: bootstrap);
    expect(allowed(password: true), isTrue);
    expect(allowed(face: true), isTrue);
    expect(allowed(face: true, opted: false), isFalse);
    expect(allowed(password: true, master: false), isFalse);
    expect(allowed(face: true, trusted: false), isFalse);
    expect(allowed(password: true, bootstrap: true), isFalse);
    expect(allowed(face: true, bootstrap: true), isFalse);
    expect(allowed(password: true, face: true, bootstrap: true), isTrue);
  });
  testWidgets('trusted master uses the existing secondary password without forcing Face', (tester) async {
    final access = _Access(); await _show(tester, access);
    await _password(tester);
    expect(access.passwords, ['existing-secondary']);
    expect(access.biometricCalls, 0);
    expect(access.bootstrapCalls, 0);
    expect(access.masterCalls, greaterThanOrEqualTo(3));
    expect(find.text('MASTER-CONTENT'), findsOneWidget);
    await _close(tester);
  });
  testWidgets('trusted opted-in Face unlock does not submit or replace secondary password', (tester) async {
    final access = _Access(); await _show(tester, access);
    await tester.tap(find.text('Face ID / Touch IDで開く')); await tester.pumpAndSettle();
    expect(access.biometricCalls, 1); expect(access.passwords, isEmpty);
    expect(find.text('MASTER-CONTENT'), findsOneWidget); await _close(tester);
  });
  testWidgets('Face preference disabled hides Face and still permits correct shared password', (tester) async {
    final access = _Access(); await _show(tester, access, opted: false);
    expect(find.text('Face ID / Touch IDで開く'), findsNothing);
    await _password(tester); expect(find.text('MASTER-CONTENT'), findsOneWidget);
    await _close(tester);
  });
  testWidgets('bootstrap captures secondary before native inactive clears field and retains AND', (tester) async {
    final access = _Access()..trusted = false..canBootstrap = true..biometricWait = Completer<bool>();
    await _show(tester, access);
    await tester.enterText(find.byType(TextField), 'existing-secondary');
    await tester.tap(find.text('本人確認してこの端末を登録')); await tester.pumpAndSettle();
    expect(access.biometricCalls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    access.biometricWait!.complete(true); await tester.pumpAndSettle();
    expect(access.passwords, ['existing-secondary']); expect(access.bootstrapCalls, 1);
    expect(find.text('MASTER-CONTENT'), findsOneWidget); await _close(tester);
  });
  testWidgets('real background invalidates late Face without bootstrap or unlock', (tester) async {
    final access = _Access()..biometricWait = Completer<bool>(); await _show(tester, access);
    await tester.tap(find.text('Face ID / Touch IDで開く')); await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    access.biometricWait!.complete(true); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing); expect(access.bootstrapCalls, 0);
    await _close(tester);
  });
  testWidgets('actor or token replacement rejects late password result', (tester) async {
    final access = _Access()..passwordWait = Completer<bool>(); await _show(tester, access);
    await tester.enterText(find.byType(TextField), 'existing-secondary');
    await tester.tap(find.text('第2パスワードで開く')); await tester.pumpAndSettle();
    access.actor = 'other-actor'; access.token = 'synthetic-token-B';
    access.passwordWait!.complete(true); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing); expect(access.bootstrapCalls, 0);
    await _close(tester);
  });
  testWidgets('server device revocation during password verification blocks unlock', (tester) async {
    final access = _Access()..passwordWait = Completer<bool>(); await _show(tester, access);
    await tester.enterText(find.byType(TextField), 'existing-secondary');
    await tester.tap(find.text('第2パスワードで開く')); await tester.pumpAndSettle();
    access.trusted = false; access.passwordWait!.complete(true); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing); expect(access.bootstrapCalls, 0);
    await _close(tester);
  });
  testWidgets('non-master and failed bootstrap biometric never submit secondary or register', (tester) async {
    final denied = _Access()..master = false; await _show(tester, denied);
    expect(find.text('MASTER-CONTENT'), findsNothing); expect(denied.passwords, isEmpty);
    await _close(tester);
    final access = _Access()..trusted = false..canBootstrap = true..bioResult = false;
    await _show(tester, access);
    await tester.enterText(find.byType(TextField), 'existing-secondary');
    await tester.tap(find.text('本人確認してこの端末を登録')); await tester.pumpAndSettle();
    expect(access.bootstrapCalls, 0); expect(access.passwords, isEmpty);
    expect(find.text('MASTER-CONTENT'), findsNothing); await _close(tester);
  });
  testWidgets('Face completion during inactive waits for resumed before any unlock', (tester) async {
    final access = _Access()..biometricWait = Completer<bool>(); await _show(tester, access);
    await tester.tap(find.text('Face ID / Touch IDで開く')); await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await tester.pump();
    access.biometricWait!.complete(true); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsOneWidget); await _close(tester);
  });
  testWidgets('paused while waiting for Face resume rejects late completion', (tester) async {
    final access = _Access()..biometricWait = Completer<bool>(); await _show(tester, access);
    await tester.tap(find.text('Face ID / Touch IDで開く')); await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await tester.pump();
    access.biometricWait!.complete(true); await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden); await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing); await _close(tester);
  });
  testWidgets('wrong shared password does not unlock or fall back to Face', (tester) async {
    final access = _Access()..passwordResult = false; await _show(tester, access);
    await _password(tester); expect(find.text('MASTER-CONTENT'), findsNothing);
    expect(access.biometricCalls, 0); expect(find.textContaining('第2パスワードが違います。'), findsOneWidget);
    await _close(tester);
  });
  testWidgets('role revoked during password verification blocks trusted entry', (tester) async {
    final access = _Access()..passwordWait = Completer<bool>(); await _show(tester, access);
    await tester.enterText(find.byType(TextField), 'existing-secondary');
    await tester.tap(find.text('第2パスワードで開く')); await tester.pumpAndSettle();
    access.master = false; access.passwordWait!.complete(true); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing); await _close(tester);
  });
  testWidgets('Face cancel does not unlock or submit password', (tester) async {
    final access = _Access()..bioResult = false; await _show(tester, access);
    await tester.tap(find.text('Face ID / Touch IDで開く')); await tester.pumpAndSettle();
    expect(find.text('MASTER-CONTENT'), findsNothing); expect(access.passwords, isEmpty);
    await _close(tester);
  });
  testWidgets('token refresh produces explicit reload and valid password works after reload', (tester) async {
    final access = _Access(); await _show(tester, access);
    access.token = 'synthetic-refreshed-token'; await _password(tester);
    expect(find.text('MASTER-CONTENT'), findsNothing);
    expect(find.textContaining('再読み込みしてください。'), findsOneWidget);
    await tester.tap(find.text('再読み込み')); await tester.pumpAndSettle();
    await _password(tester); expect(find.text('MASTER-CONTENT'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('interrupted initial load offers reload instead of a permanent spinner', (tester) async {
    final access = _Access()..configuredWait = Completer<bool>(); await _show(tester, access, settle: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive); await tester.pump();
    access.configuredWait!.complete(true);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('再読み込み'), findsOneWidget);
    access.configuredWait = null;
    await tester.tap(find.text('再読み込み')); await tester.pumpAndSettle();
    await _password(tester); expect(find.text('MASTER-CONTENT'), findsOneWidget); await _close(tester);
  });
  test('bootstrap uses the captured bearer and only the existing exact RPC target', () async {
    final calls = <http.Request>[];
    final client = SupabaseClient('https://master-bootstrap-fixture.invalid', 'public_fixture',
      headers: {'Authorization': 'Bearer synthetic-later-B'},
      authOptions: AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        expect(r.url.host, 'master-bootstrap-fixture.invalid'); calls.add(r);
        expect(r.url.path, '/rest/v1/rpc/bootstrap_first_master_device');
        expect(r.headers['Authorization'], 'Bearer synthetic-approved-A');
        expect(jsonDecode(r.body), {'p_device_key': 'synthetic-key', 'p_device_name': 'synthetic-name', 'p_device_type': 'iphone', 'p_platform': 'ios'});
        return http.Response('null', 200, headers: {'content-type': 'application/json'}, request: r);
      }));
    await bootstrapMasterDeviceWithCapturedSession(client, key: 'synthetic-key', name: 'synthetic-name', type: 'iphone', platform: 'ios', capturedToken: 'synthetic-approved-A');
    expect(calls.length, 1); await client.dispose();
  });

  test('shared secondary verification uses captured bearer without mutating client headers', () async {
    final calls = <http.Request>[];
    final client = SupabaseClient('https://master-secondary-fixture.invalid', 'public_fixture',
      headers: {'Authorization': 'Bearer synthetic-later-B'},
      authOptions: AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        expect(r.url.host, 'master-secondary-fixture.invalid'); calls.add(r);
        expect(r.url.path, '/rest/v1/rpc/verify_secondary_password');
        expect(r.headers['Authorization'], 'Bearer synthetic-approved-A');
        expect(jsonDecode(r.body), {'p_password': 'synthetic-secondary-A'});
        return http.Response('true', 200, headers: {'content-type': 'application/json'}, request: r);
      }));
    final original = Map<String, String>.from(client.headers);
    expect(await verifyMasterSharedSecondaryWithCapturedSession(client, password: 'synthetic-secondary-A', capturedToken: 'synthetic-approved-A'), isTrue);
    expect(calls.length, 1); expect(client.headers, original);
    expect(client.headers['Authorization'], 'Bearer synthetic-later-B'); await client.dispose();
  });

}
