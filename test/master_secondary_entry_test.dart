import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/features/settings/master_protected_page.dart';

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
  @override Future<bool> isMaster() async { masterCalls++; return master; }
  @override Future<Map<String,dynamic>> status(String key) async => {'trusted': trusted, 'can_bootstrap': canBootstrap};
  @override Future<bool> configured() async => configuredValue;
  @override Future<bool> biometricAvailable() async => true;
  @override Future<bool> biometric() async { biometricCalls++; return biometricWait == null ? bioResult : biometricWait!.future; }
  @override Future<bool> verify(String password) async { passwords.add(password); return passwordWait == null ? passwordResult : passwordWait!.future; }
  @override Future<void> bootstrap(String key, String name, String type, String platform) async { bootstrapCalls++; trusted = true; canBootstrap = false; }
}
Future<void> _show(WidgetTester tester, _Access access, {bool opted = true}) async {
  SharedPreferences.setMockInitialValues({'sko_master_device_key_$_actor': 'synthetic-device-key-longer-than-32-characters', 'sko_secondary_biometric_enabled_$_actor': opted});
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(MaterialApp(home: MasterProtectedPage(title: 'Master test', access: access, child: const Scaffold(body: Text('MASTER-CONTENT')))));
  await tester.pumpAndSettle();
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pump();
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
}
