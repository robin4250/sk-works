import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/data/supabase_backend.dart';
import 'package:sk_works/features/auth/auth_gate.dart';
import 'package:sk_works/features/auth/secondary_password_reset_page.dart';
import 'package:sk_works/features/auth/secondary_protected_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'https://session-fixture.invalid';
const _key = 'public_fixture';
const _actor = '20000000-0000-0000-0000-000000000001';
const _company = '10000000-0000-0000-0000-000000000001';
const _primary = 'synthetic-primary-only';
const _secondary = 'synthetic-secondary-only';
const _storageKey = 'sb-session-fixture-auth-token';
const _bioKey = 'sko_secondary_biometric_enabled_$_actor';
final _calls = <http.Request>[];
final _nativeCalls = <MethodCall>[];
bool _biometricResult = true;
late SharedPreferences _prefs;
late String _persistedBeforeRestart;
late String _tokenBeforeRestart;
String _jwt() {
  String part(Object v) => base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': _actor, 'role': 'authenticated', 'session_id': '70000000-0000-0000-0000-000000000001', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
}
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Synthetic session condition did not complete');
}
Future<void> _initialize() async {
  await Supabase.initialize(url: _url, publishableKey: _key, debug: false,
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: false, detectSessionInUri: false),
    httpClient: MockClient((r) async {
      expect(r.url.host, 'session-fixture.invalid');
      _calls.add(r);
      http.Response json(Object? v, [int status = 200]) => http.Response(jsonEncode(v), status, headers: {'content-type': 'application/json'}, request: r);
      if (r.url.path == '/auth/v1/token') {
        expect(r.url.queryParameters['grant_type'], 'password');
        expect(jsonDecode(r.body), containsPair('password', _primary));
        return json({'access_token': _jwt(), 'refresh_token': 'synthetic-refresh-only', 'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': _actor, 'aud': 'authenticated', 'phone': '+819012345678', 'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}, 'created_at': '2026-10-16T00:00:00Z'}});
      }
      if (r.url.path == '/auth/v1/logout') return http.Response('', 204, request: r);
      if (r.url.path == '/rest/v1/rpc/employee_onboarding_state') return json(null);
      if (r.url.path == '/rest/v1/company_members') return json([{'company_id': _company}]);
      if (r.url.path == '/rest/v1/rpc/admin_initial_setup_state') return json({'required': false, 'completed': true});
      if (r.url.path == '/rest/v1/rpc/secondary_password_configured') return json(true);
      if (r.url.path == '/rest/v1/rpc/reauthentication_capabilities') return json({'protocol': 'sko-reauthentication-v1', 'secondary_password': false, 'master_feature': false, 'master_security': false});
      if (r.url.path == '/rest/v1/rpc/set_secondary_password') {
        expect(Supabase.instance.client.auth.currentUser?.id, _actor);
        expect(r.headers['authorization'], 'Bearer ${Supabase.instance.client.auth.currentSession!.accessToken}');
        expect(jsonDecode(r.body), {'p_password': _secondary});
        return json(null);
      }
      throw StateError('Unexpected endpoint; primary update/SMS are forbidden in this fixture: ${r.url.path}');
    }));
}
Future<void> _settle(WidgetTester tester) async {
  // The real SDK emits asynchronous auth/storage callbacks outside fake time.
  // Drain those callbacks before settling the actual gate's subsequent frame.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}
Widget _gate() => MaterialApp(home: SupabaseAuthGate(homeBuilder: (logout) => Scaffold(body: Column(children: [
  const Text('synthetic authenticated home'),
  TextButton(onPressed: logout, child: const Text('fixture logout')),
  Builder(builder: (context) => TextButton(onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const SecondaryProtectedPage(title: 'synthetic invoice', child: Text('protected fixture')))), child: const Text('fixture protected entry'))),
]))));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('SKO_SESSION_CHAIN_FIXTURE')) {
    test('session chain uses dedicated synthetic configuration', () {},
      skip: 'Run the dedicated workflow with fixed synthetic compile-time settings.');
    return;
  }
  setUpAll(() async {
    // Fail before any initialization if the workflow accidentally supplies real configuration.
    expect(SupabaseBackendConfig.url, _url);
    expect(SupabaseBackendConfig.publishableKey, _key);
    SharedPreferences.setMockInitialValues({_bioKey: true});
    _prefs = await SharedPreferences.getInstance();
    await _initialize();
    final original = Supabase.instance.client;
    await SupabaseBackend.initializeIfConfigured();
    expect(SupabaseBackend.isInitialized, true);
    expect(identical(SupabaseBackend.client, original), true);
    await original.auth.signInWithPassword(phone: '+819012345678', password: _primary);
    await _until(() => _prefs.getString(_storageKey) != null);
    _persistedBeforeRestart = _prefs.getString(_storageKey)!;
    _tokenBeforeRestart = original.auth.currentSession!.accessToken;
    final requestCount = _calls.length;
    await Supabase.instance.dispose();
    expect(_prefs.getString(_storageKey), _persistedBeforeRestart);
    expect(_prefs.getBool(_bioKey), true);
    await _initialize();
    await _until(() => Supabase.instance.client.auth.currentUser?.id == _actor);
    expect(_calls.length, requestCount); // Unexpired restore does not password-login or send OTP.
    expect(Supabase.instance.client.auth.currentSession!.accessToken, _tokenBeforeRestart);
  });
  tearDownAll(() async { await Supabase.instance.dispose(); });
  testWidgets('SDK persisted restart then explicit logout and login reaches existing secondary Face reset only', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const channel = MethodChannel('plugins.flutter.io/local_auth');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      _nativeCalls.add(call);
      switch (call.method) {
        case 'getAvailableBiometrics': return ['face'];
        case 'deviceSupportsBiometrics':
        case 'isDeviceSupported': return true;
        case 'authenticate': return _biometricResult;
        case 'stopAuthentication': return true;
        default: throw StateError('Unexpected local_auth method ${call.method}');
      }
    });
    addTearDown(() { tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null); });
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_gate()); await _settle(tester);
    expect(find.text('synthetic authenticated home'), findsOneWidget);
    expect(find.text('本パスワードを忘れた方'), findsNothing);
    expect(_prefs.getString(_storageKey), _persistedBeforeRestart);
    await tester.runAsync(() async {
      await tester.tap(find.text('fixture logout'));
      await _until(() => Supabase.instance.client.auth.currentSession == null && !_prefs.containsKey(_storageKey));
    });
    await _settle(tester);
    expect(find.text('本パスワードを忘れた方'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentUser, isNull);
    expect(_prefs.containsKey(_storageKey), false);
    expect(_prefs.getBool(_bioKey), true);
    final writes = _calls.where((r) => r.url.path.endsWith('/set_secondary_password')).length;
    // The actual device access refuses the save when no authenticated global repository actor exists.
    final loggedOutAccess = DeviceSecondaryPasswordResetAccess();
    await tester.runAsync(() async { await expectLater(loggedOutAccess.loadRequirement(), throwsStateError); await expectLater(loggedOutAccess.save(_secondary), throwsStateError); });
    expect(_calls.where((r) => r.url.path.endsWith('/set_secondary_password')).length, writes);
    await tester.enterText(find.byType(TextField).at(0), '09012345678');
    await tester.enterText(find.byType(TextField).at(1), _primary);
    await tester.runAsync(() async {
      await tester.tap(find.text('ログイン').last);
      await _until(() => Supabase.instance.client.auth.currentUser?.id == _actor);
    });
    await _settle(tester);
    expect(find.text('synthetic authenticated home'), findsOneWidget);
    await tester.tap(find.text('fixture protected entry')); await _settle(tester);
    expect(find.text('第2認証が必要です'), findsOneWidget);
    await tester.tap(find.text('第2パスワードを再設定')); await _settle(tester);
    expect(find.text('第2パスワードを再設定'), findsOneWidget);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    await tester.tap(find.text('本人確認する')); await _settle(tester);
    expect(_nativeCalls.where((c) => c.method == 'authenticate').length, 1);
    expect(find.byKey(const Key('reset-password')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reset-password')), _secondary);
    await tester.enterText(find.byKey(const Key('reset-confirm')), _secondary);
    await tester.runAsync(() async {
      await tester.tap(find.text('再設定する'));
      await _until(() => _calls.any((r) => r.url.path.endsWith('/set_secondary_password')));
    });
    await _settle(tester);
    expect(find.text('第2パスワードを再設定しました。新しいパスワードで認証してください。'), findsOneWidget);
    expect(_calls.where((r) => r.url.path.endsWith('/set_secondary_password')).length, 1);
    expect(Supabase.instance.client.auth.currentUser!.id, _actor);
    expect(_prefs.getBool(_bioKey), true);
    expect(_prefs.getString(_storageKey), isNotNull);
    expect(_calls.where((r) => r.url.path == '/auth/v1/token').length, 2);
    expect(_calls.where((r) => r.url.path == '/auth/v1/logout').length, 1);
    expect(_calls.where((r) => r.url.path == '/auth/v1/user' || r.url.path == '/auth/v1/otp' || r.url.path.contains('master_recovery')), isEmpty);
    // Cancelled Face prompt cannot reveal replacement fields or write again.
    _biometricResult = false;
    await tester.tap(find.text('第2パスワードを再設定')); await _settle(tester);
    await tester.tap(find.text('本人確認する')); await _settle(tester);
    expect(find.byKey(const Key('reset-password')), findsNothing);
    expect(_calls.where((r) => r.url.path.endsWith('/set_secondary_password')).length, 1);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
