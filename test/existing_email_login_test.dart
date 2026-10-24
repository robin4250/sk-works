import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sk_works/features/auth/secure_onboarding_pages.dart';
import 'package:sk_works/features/auth/secure_onboarding_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SecureOnboardingRepository repository;
  late List<http.Request> requests;
  late Completer<http.Response> response;
  setUp(() {
    requests = [];
    response = Completer<http.Response>();
    client = SupabaseClient(
      'https://email-login-fixture.invalid', 'public-fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return response.future;
      }),
    );
    repository = SecureOnboardingRepository.forClient(client);
  });
  tearDown(() async => client.dispose());

  test('existing email uses password grant only; no signup or identity mutation', () async {
    final login = repository.signInWithEmail(email: ' user@example.com ', password: 'existing-password');
    response.complete(http.Response('{"error":"invalid_grant","error_description":"Invalid login credentials"}', 400,
      headers: {'content-type': 'application/json'}));
    await expectLater(login, throwsA(isA<AuthException>()));
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/token');
    expect(requests.single.url.queryParameters['grant_type'], 'password');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['email'], 'user@example.com');
    expect(body['password'], 'existing-password');
    expect(body['phone'], isNull);
    expect(client.auth.currentSession, isNull);
  });

  test('malformed email stops before sending credentials', () async {
    for (final email in ['09012345678', '', 'a@@example.com', 'a b@example.com']) {
      await expectLater(repository.signInWithEmail(email: email, password: 'existing-password'), throwsArgumentError);
    }
    expect(requests, isEmpty);
  });

  Future<void> show(WidgetTester tester, VoidCallback done) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: SecureAuthPage(repository: repository, onAuthenticated: done)));
    await tester.pumpAndSettle();
  }

  testWidgets('email switch clears credentials and keeps phone registration and QR', (tester) async {
    await show(tester, () {});
    await tester.enterText(find.byType(TextField).at(0), '09012345678');
    await tester.enterText(find.byType(TextField).at(1), 'phone-password');
    await tester.tap(find.text('登録済みのメールでログインする'));
    await tester.pumpAndSettle();
    expect(find.text('メールアドレスでログイン'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, isEmpty);
    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'email-password');
    await tester.tap(find.text('電話番号でログインする'));
    await tester.pumpAndSettle();
    expect(find.text('携帯電話番号（ID）'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, isEmpty);
    expect(find.text('従業員登録QRでログイン'), findsOneWidget);
    expect(find.text('管理者として初めて登録する'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('email submission disables mode changes; rejected login never completes', (tester) async {
    var authenticated = 0;
    await show(tester, () => authenticated++);
    await tester.tap(find.text('登録済みのメールでログインする'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'email-password');
    await tester.tap(find.text('ログイン').last);
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '電話番号でログインする')).onPressed, isNull);
    expect(requests, hasLength(1));
    await tester.runAsync(() async {
      response.complete(http.Response('{"error":"invalid_grant","error_description":"Invalid login credentials"}', 400,
        headers: {'content-type': 'application/json'}));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(authenticated, 0);
    expect(find.text('登録済みのメールアドレスまたは本パスワードを確認してください。'), findsOneWidget);
    expect(find.text('メールアドレスでログイン'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '電話番号でログインする')).onPressed, isNotNull);
  });

  testWidgets('existing email session completes with the same returned user', (tester) async {
    const id = '20000000-0000-0000-0000-000000000001';
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token = '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.synthetic';
    var authenticated = 0;
    await show(tester, () => authenticated++);
    await tester.tap(find.text('登録済みのメールでログインする'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'email-password');
    await tester.tap(find.text('ログイン').last);
    await tester.pump();
    await tester.runAsync(() async {
      response.complete(http.Response(jsonEncode({
        'access_token': token, 'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': id, 'aud': 'authenticated', 'email': 'user@example.com', 'created_at': '2026-10-20T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}},
      }), 200, headers: {'content-type': 'application/json'}));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(authenticated, 1);
    expect(client.auth.currentUser!.id, id);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/token');
  });

  testWidgets('entering admin registration from email returns to clean phone registration', (tester) async {
    await show(tester, () {});
    await tester.tap(find.text('登録済みのメールでログインする'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'user@example.com');
    await tester.tap(find.text('管理者として初めて登録する'));
    await tester.pumpAndSettle();
    expect(find.text('携帯電話番号（ID）'), findsOneWidget);
    expect(find.text('登録済みメールアドレス'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, isEmpty);
    expect(requests, isEmpty);
  });
  testWidgets('Google account email guidance uses saved SKO password without signout', (tester) async {
    await show(tester, () {});
    await tester.tap(find.text('登録済みのメールでログインする'));
    await tester.pumpAndSettle();
    expect(find.text('確認済みメールと、SKOに保存した第一パスワードでログインします。電話番号の登録は不要です。'), findsOneWidget);
    await tester.tap(find.text('？ メールでログインするには'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Googleで使っている同じSKOアカウントでも'), findsOneWidget);
    expect(find.textContaining('現在ログイン中ならログアウトせずに設定できます。'), findsOneWidget);
    expect(find.textContaining('Google用のパスワードとは別です。'), findsOneWidget);
    expect(requests, isEmpty);
    expect(client.auth.currentSession, isNull);
  });

}
