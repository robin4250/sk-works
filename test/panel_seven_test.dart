import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/panel_seven_page.dart';
import 'package:sk_works/features/auth/panel_seven_repository.dart';

Map<String, dynamic> user(String id) => {
  'id': id, 'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z',
  'app_metadata': {'provider': 'google'},
  'email': 'owner@example.test',
  'email_confirmed_at': '2026-01-01T00:00:00Z',
  'identities': [
    {'id': id, 'identity_id': id, 'user_id': id, 'provider': 'google',
     'identity_data': {'sub': id}, 'created_at': '2026-01-01T00:00:00Z',
     'updated_at': '2026-01-01T00:00:00Z'},
  ],
};
String session(String id) => jsonEncode({
  'access_token': '${base64Url.encode(utf8.encode("{}"))}.${base64Url.encode(utf8.encode(jsonEncode({
    "sub": id, "exp": 4102444800, "amr": [{"method": "oauth"}],
  })))}.synthetic',
  'refresh_token': 'synthetic-refresh', 'token_type': 'bearer',
  'expires_in': 3600, 'user': user(id),
});

PanelSevenSnapshot snapshot() => const PanelSevenSnapshot(
  actorId: 'a', providers: ['google'], email: 'owner@example.test',
  phone: null, emailConfirmed: true, phoneConfirmed: false,
  sessionMethods: ['oauth'], secondaryConfigured: true,
  accessToken: 'synthetic',
);

class FakeRepository extends PanelSevenRepository {
  FakeRepository() : super(SupabaseClient('http://127.0.0.1:1', 'synthetic'));
  bool current = true;
  int loads = 0;
  Future<PanelSevenSnapshot>? nextLoad;
  final events = StreamController<AuthState>.broadcast();
  @override
  Stream<AuthState> get changes => events.stream;
  @override
  bool isCurrent(PanelSevenSnapshot snapshot) => current;
  @override
  Future<PanelSevenSnapshot> load() async {
    loads++;
    final pending = nextLoad;
    nextLoad = null;
    if (pending != null) return pending;
    if (!current) throw StateError('changed');
    return snapshot();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
    'sko_secondary_biometric_enabled_a': true,
    'sko_secondary_biometric_enabled_b': false,
  }));
  test('reads original JWT and own providers without mutation or signup', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final paths = <String>[];
    final headers = <String?>[];
    server.listen((request) async {
      paths.add('${request.method} ${request.uri.path}');
      headers.add(request.headers.value('Authorization'));
      request.response.headers.contentType = ContentType.json;
      request.response.write(request.uri.path.endsWith('/user')
          ? jsonEncode(user('a')) : 'true');
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic');
    addTearDown(client.dispose);
    await client.auth.setInitialSession(session('a'));
    final token = client.auth.currentSession!.accessToken;
    final before = client.auth.currentSession;
    final repository = PanelSevenRepository(client,
        biometricAvailability: () async => true);
    final value = await repository.load();
    expect(value.providers, ['google']);
    expect(value.biometricEnabled, isTrue);
    expect(value.biometricAvailable, isTrue);
    expect(value.phone, isNull);
    expect(value.secondaryConfigured, isTrue);
    expect(value.sessionMethods, ['oauth']);
    expect(repository.isCurrent(value), isTrue);
    expect(paths, ['GET /auth/v1/user',
      'POST /rest/v1/rpc/secondary_password_configured']);
    expect(headers, everyElement('Bearer $token'));
    expect(identical(client.auth.currentSession, before), isTrue);
  });

  test('actor changes while getUser is pending reject response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<void>();
    final release = Completer<void>();
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      received.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(user('a')));
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic');
    addTearDown(client.dispose);
    await client.auth.setInitialSession(session('a'));
    final pending = PanelSevenRepository(client).load();
    final check = expectLater(pending, throwsStateError);
    await received.future;
    await client.auth.setInitialSession(session('b'));
    release.complete();
    await check;
    expect(client.auth.currentUser!.id, 'b');
    expect(paths, ['/auth/v1/user']);
  });

  test('secondary status failure is unknown, never unconfigured', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/user')) {
        request.response.write(jsonEncode(user('a')));
      } else {
        request.response.statusCode = 403;
        request.response.write('{"code":"42501","message":"denied"}');
      }
      await request.response.close();
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic');
    addTearDown(client.dispose);
    await client.auth.setInitialSession(session('a'));
    expect((await PanelSevenRepository(client).load()).secondaryConfigured,
        isNull);
  });

  testWidgets('shows linked Google separately from actual session method and passwords',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(repository.events.close);
    addTearDown(repository.client.dispose);
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('外部アカウント認証（提供元は特定できません）'), findsOneWidget);
    expect(find.textContaining('設定状況は確認できません'), findsOneWidget);
    expect(find.text('設定済み'), findsOneWidget);
    expect(find.text('Master 緊急復旧設定'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('actor change removes old personal details and shows retry',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(repository.events.close);
    addTearDown(repository.client.dispose);
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    repository.current = false;
    repository.events.add(const AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();
    expect(find.text('owner@example.test'), findsNothing);
    expect(find.text('本人のアカウント情報を確認できませんでした。'), findsOneWidget);
  });

  testWidgets('help explains local biometrics without claiming server MFA',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(repository.events.close);
    addTearDown(repository.client.dispose);
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('使い方'));
    await tester.pumpAndSettle();
    expect(find.text('アカウント設定について'), findsOneWidget);
    expect(find.textContaining('端末内の本人確認'), findsWidgets);
  });
  testWidgets('background events and late pending reads cannot restore personal data',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(repository.events.close);
    addTearDown(repository.client.dispose);
    final pending = Completer<PanelSevenSnapshot>();
    repository.nextLoad = pending.future;
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    expect(repository.loads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.events.add(const AuthState(AuthChangeEvent.tokenRefreshed, null));
    pending.complete(snapshot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(repository.loads, 1);
    expect(find.text('Google'), findsNothing);
    expect(find.textContaining('owner@example.test'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
    expect(find.text('Google'), findsOneWidget);
  });

}
