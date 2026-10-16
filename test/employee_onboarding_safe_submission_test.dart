import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only transport injection; http is pinned by the repository lockfile.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sk_works/features/auth/employee_onboarding_pages.dart';
import 'package:sk_works/features/auth/employee_onboarding_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
const capName = 'employee_onboarding_photo_capability';
const safeName = 'save_employee_onboarding_profile_without_photos';
const oldName = 'save_employee_onboarding_profile';

class Fixture {
  late final SupabaseClient client;
  late final EmployeeOnboardingRepository repository;
  final requests = <http.Request>[];
  Object? capability = {'has_existing_images': true, 'photo_upload_allowed': false};
  String? capError;
  String? saveError;
  String nextActor = actor;
  int caps = 0;
  Future<void> Function(int count)? onCap;
  Future<void> Function(int count)? onUpload;
  int uploads = 0;

  Future<void> start() async {
    client = SupabaseClient('https://synthetic-onboarding.invalid', 'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(respond));
    repository = EmployeeOnboardingRepository(client);
    await login(actor);
    requests.clear();
  }

  Future<void> login(String id) async {
    nextActor = id;
    await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'synthetic');
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/auth/v1/token') {
      String encode(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token = '${encode({'alg': 'HS256'})}.${encode({'sub': nextActor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj';
      return json({'access_token': token, 'refresh_token': 'synthetic', 'token_type': 'bearer', 'expires_in': 3600,
        'user': {'id': nextActor, 'aud': 'authenticated', 'role': 'authenticated', 'email': 'fixture@example.invalid', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-01-01T00:00:00Z'}});
    }
    if (path.endsWith('/$capName')) {
      caps++;
      await onCap?.call(caps);
      if (capError != null) return error(capError!);
      return json(capability);
    }
    if (path.startsWith('/storage/v1/object/')) {
      uploads++;
      await onUpload?.call(uploads);
      return json({'Key': path.substring('/storage/v1/object/'.length), 'Id': 'synthetic'});
    }
    if (path.endsWith('/$safeName') || path.endsWith('/$oldName')) {
      if (saveError != null) return error(saveError!);
      return http.Response('', 204);
    }
    return error('PGRST202');
  }

  http.Response json(Object? value, [int status = 200]) => http.Response(jsonEncode(value), status, headers: {'content-type': 'application/json'});
  http.Response error(String code) => json({'code': code, 'message': 'synthetic rejection', 'details': null, 'hint': null}, code == 'PGRST202' ? 404 : 403);
  Iterable<http.Request> named(String name) => requests.where((r) => r.url.path.endsWith('/$name'));
  Iterable<http.Request> get storage => requests.where((r) => r.url.path.startsWith('/storage/'));
}

Future<void> showPage(WidgetTester tester, Fixture fixture, VoidCallback submitted) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: EmployeeProfileOnboardingPage(
    name: 'synthetic', repository: fixture.repository, onSubmitted: submitted, onSignOut: () async {},
    imagePicker: (_) async => XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'synthetic.jpg'),
  )));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester) async {
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(6));
  for (var i = 0; i < 6; i++) {
    await tester.enterText(fields.at(i), 'synthetic field $i');
  }
}

Future<void> photos(WidgetTester tester) async {
  for (final label in ['本人の写真 *', 'マイナンバーカード 表面 *', 'マイナンバーカード 裏面 *']) {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('写真から選ぶ'));
    await tester.pumpAndSettle();
  }
}

Future<void> send(WidgetTester tester) async {
  await tester.tap(find.text('本登録を申請'));
  await tester.pumpAndSettle();
}

void main() {
  late Fixture f;
  setUp(() async { f = Fixture(); await f.start(); });
  tearDown(() async { await f.client.dispose(); });

  test('capability accepts exactly two booleans without coercion or extra PII', () {
    for (final existing in [true, false]) {
      for (final allowed in [true, false]) {
        final parsed = EmployeeOnboardingPhotoCapability.parse({'has_existing_images': existing, 'photo_upload_allowed': allowed});
        expect(parsed.hasExistingImages, existing);
        expect(parsed.photoUploadAllowed, allowed);
      }
    }
    for (final bad in [null, [], {}, {'has_existing_images': true}, {'has_existing_images': 1, 'photo_upload_allowed': false}, {'has_existing_images': true, 'photo_upload_allowed': 'false'}, {'has_existing_images': true, 'photo_upload_allowed': false, 'path': 'forbidden'}]) {
      expect(() => EmployeeOnboardingPhotoCapability.parse(bad), throwsFormatException);
    }
  });

  test('only missing capability PGRST202 selects legacy, other errors propagate', () async {
    final request = f.repository.beginRequest(() => true);
    f.capError = 'PGRST202';
    expect(await f.repository.loadPhotoCapability(request: request), isNull);
    for (final code in ['42501', '42883', 'PGRST301']) {
      f.capError = code;
      await expectLater(f.repository.loadPhotoCapability(request: request), throwsA(isA<PostgrestException>()));
    }
  });

  testWidgets('paused photos omit upload and use only new seven-text RPC', (tester) async {
    var submitted = 0;
    await showPage(tester, f, () => submitted++);
    await fill(tester);
    await send(tester);
    expect(submitted, 1);
    expect(f.storage, isEmpty);
    expect(f.named(oldName), isEmpty);
    final request = f.named(safeName).single;
    final fields = jsonDecode(request.body) as Map;
    expect(fields.length, 7);
    expect(fields.keys.where((key) => key.toString().contains('path')), isEmpty);
    expect(f.caps, 3); // Initial display, submission start, immediate pre-dispatch.
  });

  for (final legacy in [true, false]) {
    testWidgets('${legacy ? 'missing capability' : 'upload allowed'} preserves three-photo legacy submission', (tester) async {
      if (legacy) { f.capError = 'PGRST202'; } else { f.capability = {'has_existing_images': false, 'photo_upload_allowed': true}; }
      var submitted = 0;
      await showPage(tester, f, () => submitted++);
      await fill(tester);
      await send(tester);
      expect(f.storage, isEmpty);
      expect(f.named(oldName), isEmpty);
      await photos(tester);
      await send(tester);
      expect(submitted, 1);
      expect(f.storage, hasLength(3));
      expect(f.named(oldName), hasLength(1));
      expect(f.named(safeName), isEmpty);
      final fields = jsonDecode(f.named(oldName).single.body) as Map;
      for (final key in ['p_portrait_path', 'p_my_number_front_path', 'p_my_number_back_path']) { expect(fields[key], startsWith('$actor/')); }
      final authorization = f.client.auth.currentSession!.accessToken;
      for (final r in [...f.storage, ...f.named(oldName)]) { expect(r.headers['authorization'], 'Bearer $authorization'); }
    });
  }

  for (final error in ['PGRST202', '42501', '55000']) {
    testWidgets('new save $error never falls back and preserves text and photo draft', (tester) async {
      f.saveError = error;
      var submitted = 0;
      await showPage(tester, f, () => submitted++);
      await fill(tester);
      await photos(tester);
      await send(tester);
      expect(submitted, 0);
      expect(f.named(safeName), hasLength(1));
      expect(f.named(oldName), isEmpty);
      expect(f.storage, isEmpty);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'synthetic field 0');
      expect(find.textContaining('本人情報を送信できませんでした。入力内容は保持'), findsOneWidget);
    });
  }

  for (final mode in ['malformed', 'denied', 'network', 'changed', 'actor', 'background']) {
    testWidgets('$mode on pre-dispatch capability stops writes and retains input', (tester) async {
      var submitted = 0;
      await showPage(tester, f, () => submitted++);
      await fill(tester);
      f.onCap = (count) async {
        if (count != 3) return;
        if (mode == 'network') throw http.ClientException('synthetic offline');
        if (mode == 'malformed') f.capability = {'photo_upload_allowed': false};
        if (mode == 'denied') f.capError = '42501';
        if (mode == 'changed') f.capError = 'PGRST202';
        if (mode == 'actor') await f.login(other);
        if (mode == 'background') tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      };
      await send(tester);
      expect(submitted, 0);
      expect(f.named(oldName), isEmpty);
      expect(f.named(safeName), isEmpty);
      expect(f.storage, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'synthetic field 0');
      if (mode == 'background') tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  }

  testWidgets('actor switch after first upload stops subsequent uploads and saves without deleting', (tester) async {
    f.capError = 'PGRST202';
    var submitted = 0;
    await showPage(tester, f, () => submitted++);
    await fill(tester);
    await photos(tester);
    f.onUpload = (_) => f.login(other);
    await send(tester);
    expect(submitted, 0);
    expect(f.storage, hasLength(1));
    expect(f.named(oldName), isEmpty);
    expect(f.named(safeName), isEmpty);
    expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
    // Switching back cannot revive the old screen's draft for submission.
    await f.login(actor);
    await tester.pumpAndSettle();
    await send(tester);
    expect(f.storage, hasLength(1));
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
  });
}
