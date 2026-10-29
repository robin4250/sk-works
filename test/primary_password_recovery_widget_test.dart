import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/secure_onboarding_pages.dart';
import 'package:sk_works/features/auth/secure_onboarding_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _id = '20000000-0000-0000-0000-000000000001';
Map<String, dynamic> _user() => {'id': _id, 'aud': 'authenticated', 'app_metadata': <String, dynamic>{}, 'user_metadata': <String, dynamic>{}, 'created_at': '2026-10-16T00:00:00Z'};
String _token() {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': _id, 'session_id':'20000000-0000-0000-0000-000000000099', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
}
class _Wire {
  _Wire() {
    client = SupabaseClient('https://primary-recovery-fixture.invalid', 'public_fixture', authOptions: const AuthClientOptions(autoRefreshToken: false), httpClient: MockClient((r) async {
      calls.add(r);
      if (r.url.path == '/auth/v1/signup') return http.Response(jsonEncode({'user': _user()}), 200, headers: {'content-type': 'application/json'}, request: r);
      if (r.url.path == '/auth/v1/token' || r.url.path == '/auth/v1/verify') return http.Response(jsonEncode({'access_token': _token(), 'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600, 'user': _user()}), 200, headers: {'content-type': 'application/json'}, request: r);
      if (r.url.path == '/auth/v1/resend') return http.Response('{}', 200, headers: {'content-type': 'application/json'}, request: r);
      throw StateError('Unexpected authentication request: ${r.url.path}');
    }));
    repository = SecureOnboardingRepository.forClient(client);
  }
  late final SupabaseClient client;
  late final SecureOnboardingRepository repository;
  final calls = <http.Request>[];
}
Future<void> _show(WidgetTester tester, _Wire w, VoidCallback onAuthenticated) async {
  debugPrint('primary fixture: prepare surface');
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  debugPrint('primary fixture: mount');
  await tester.pumpWidget(MaterialApp(home: SecureAuthPage(repository: w.repository, onAuthenticated: onAuthenticated)));
  debugPrint('primary fixture: mounted');
}
// The pinned SDK subscription cancellation may complete in the real setup
// zone; drain that work as well as Flutter's fake UI scheduler.
Future<void> _settleAuth(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async { await Future<void>.delayed(Duration.zero); });
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}
void main() {
  late List<_Wire> wires;
  setUpAll(() { wires = List.generate(3, (_) => _Wire()); });
  tearDownAll(() async { for (final w in wires) { await w.client.dispose(); } });
  testWidgets('forgot is unavailable: no SMS, no update, no fake biometric and back clears credentials', (tester) async {
    final w = wires[0]; var authenticated = 0;
    await _show(tester, w, () => authenticated++);
    await tester.enterText(find.byType(TextField).at(0), '09012345678');
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.tap(find.text('本パスワードを忘れた方')); await tester.pumpAndSettle();
    expect(find.textContaining('本パスワードはログイン用で、第2パスワードとは別です。'), findsOneWidget);
    expect(find.textContaining('本パスワードは変わりません。'), findsOneWidget);
    expect(find.textContaining('Googleでログインできる方は'), findsOneWidget);
    expect(find.textContaining('アカウント設定で第一パスワードを設定・変更できます。'), findsOneWidget);
    expect(find.textContaining('登録済みの電話番号または確認済みメールと、保存した本パスワードを使います。'), findsOneWidget);
    expect(find.textContaining('Google用のパスワードとは別です。'), findsOneWidget);
    expect(find.textContaining('この画面からの再設定・SMS復旧は利用できません。'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('本人確認SMSを送信'), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
    expect(w.calls, isEmpty); expect(authenticated, 0); expect(w.client.auth.currentSession, isNull);
    await tester.tap(find.text('通常ログインへ戻る')); await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('本パスワード（ログイン用）'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, isEmpty);
    expect(find.text('従業員登録QRでログイン'), findsOneWidget);
    expect(w.calls, isEmpty);
    debugPrint('primary fixture: forgot assertions complete');
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('ordinary phone password login still authenticates through SDK', (tester) async {
    final w = wires[1]; var authenticated = 0;
    await _show(tester, w, () => authenticated++);
    await tester.enterText(find.byType(TextField).at(0), '09012345678');
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.tap(find.text('ログイン').last); await _settleAuth(tester);
    expect(authenticated, 1); expect(w.client.auth.currentUser!.id, _id);
    expect(w.calls.length, 1);
    expect(w.calls.single.url.path, '/auth/v1/token');
    expect(w.calls.single.url.queryParameters['grant_type'], 'password');
    expect(jsonDecode(w.calls.single.body), containsPair('phone', '+819012345678'));
    expect(w.calls.where((r) => r.url.path == '/auth/v1/otp' || r.url.path == '/auth/v1/user'), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('initial registration retains separate SMS verification, QR entry and no recovery reset', (tester) async {
    final w = wires[2]; var authenticated = 0;
    await _show(tester, w, () => authenticated++);
    expect(find.text('従業員登録QRでログイン'), findsOneWidget);
    await tester.tap(find.text('管理者として初めて登録する')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '09012345678');
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    await tester.enterText(find.byType(TextField).at(2), 'synthetic-password');
    await tester.tap(find.text('登録してSMS認証へ')); await _settleAuth(tester);
    expect(w.calls.single.url.path, '/auth/v1/signup');
    expect(find.text('承認コード'), findsWidgets); expect(authenticated, 0);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('承認する')); await _settleAuth(tester);
    expect(authenticated, 1);
    expect(w.calls.last.url.path, '/auth/v1/verify');
    expect(w.calls.where((r) => r.url.path == '/auth/v1/otp' || r.url.path == '/auth/v1/user'), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

