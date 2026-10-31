import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/profile/profile_page.dart';
import 'package:sk_works/features/profile/profile_repository.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const worker = '10000000-0000-0000-0000-000000000003';
const sidA = '10000000-0000-0000-0000-000000000004';
const sidB = '10000000-0000-0000-0000-000000000005';
const foreign = '10000000-0000-0000-0000-000000000006';
const requestId = '10000000-0000-0000-0000-000000000007';
const family = <Map<String, dynamic>>[
  {'id': foreign, 'name': 'Synthetic child', 'relation': '子',
    'birth_date': '2020-02-02', 'is_dependent': true},
];
Map<String, dynamic> payload() => {
  'name': 'Synthetic employee', 'kind': 'employee', 'blood_type': '',
  'role': '', 'phone': '', 'address': '', 'emergency_name': '',
  'emergency_relation': '', 'emergency_phone': '', 'emergency_address': '',
  'family_composition': '', 'family_members': family,
};

class Wire {
  String sid = sidA;
  Object? contract = 1;
  Object? birthday = '1980-01-15';
  String returnedWorker = worker;
  List<Map<String, dynamic>> members = [{'company_id': company, 'role': 'owner'}];
  List<Map<String, dynamic>> workers = [{'id': worker}];
  bool pending = false, loseSaveAck = false, malformedSave = false;
  bool holdProfile = false;
  Completer<void>? entered, release;
  final requests = <http.Request>[];
  final writes = <Map<String, dynamic>>[];
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  late final client = SupabaseClient('https://synthetic.invalid', 'synthetic-public',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(respond));
  late final repository = ProfileRepository.forClient(client);

  String token(String session) {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': actor, 'session_id': session,
      'exp': expiry, 'role': 'authenticated', 'is_anonymous': false})}.synthetic';
  }
  Future<void> login(String session) async {
    sid = session;
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic');
    await Future<void>.delayed(Duration.zero);
  }
  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    Object? value;
    switch (request.url.path) {
      case '/auth/v1/token':
        value = {'access_token': token(sid), 'refresh_token': 'synthetic',
          'expires_in': 3600, 'token_type': 'bearer', 'user': {
            'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
            'is_anonymous': false, 'email': 'synthetic@example.invalid',
            'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-10-31T00:00:00Z'}};
      case '/rest/v1/company_members': value = members;
      case '/rest/v1/workers': value = workers;
      case '/rest/v1/companies': value = [{'name': 'Synthetic company'}];
      case '/rest/v1/user_profiles': value = [{'display_name': 'Synthetic employee', 'phone': ''}];
      case '/rest/v1/rpc/ensure_personal_sko_id': value = 'SKO-SYNTHETIC';
      case '/rest/v1/rpc/current_worker_personnel_profile':
        value = {...payload(), 'worker_id': returnedWorker,
          if (contract != null) 'birth_date_contract_version': contract,
          if (contract != null) 'birth_date': birthday};
        if (holdProfile) {
          entered?.complete();
          await release!.future;
        }
      case '/rest/v1/rpc/save_worker_personnel_profile':
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        writes.add(body);
        final submitted = body['p_payload'] as Map;
        if (!pending && submitted.containsKey('birth_date')) birthday = submitted['birth_date'];
        if (loseSaveAck) throw http.ClientException('synthetic response lost');
        value = malformedSave ? <String, dynamic>{} : pending
            ? {'status': 'pending', 'requires_approval': true, 'saved_directly': false,
                'request_id': requestId, 'required_approvals': 1}
            : {'status': 'saved', 'requires_approval': false, 'saved_directly': true};
      default: throw StateError('Unexpected synthetic endpoint: ${request.url.path}');
    }
    return http.Response(jsonEncode(value), 200,
      headers: {'content-type': 'application/json'}, request: request);
  }
  Future<ProfileBirthdayEvidence> load() => repository.loadOwnBirthday(workerId: worker, companyId: company);
  Future<Map<String, dynamic>> save(ProfileBirthdayEvidence evidence, Object? value) =>
    repository.savePersonnelProfile(workerId: worker,
      birthdayEvidence: evidence, payload: {...payload(), 'birth_date': value});
}

Future<void> showProfile(WidgetTester tester, Wire wire) async {
  await tester.pumpWidget(MaterialApp(home: ProfilePage(role: ManualRole.admin,
    repository: wire.repository)));
  await tester.pumpAndSettle();
}
Future<void> saveProfile(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('profile-personnel-save'));
  await tester.scrollUntilVisible(save, 500, scrollable: find.byType(Scrollable).first);
  await tester.tap(save);
  await tester.pumpAndSettle();
  await tester.tap(find.text('確定して保存'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old contract cannot save own birthday or substitute the family birthday', () async {
    final w = Wire()..contract = null; addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    expect(evidence.supported, isFalse); expect(evidence.birthDate, isNull);
    await expectLater(w.save(evidence, '1981-01-01'), throwsStateError);
    expect(w.writes, isEmpty);
  });
  test('birthday evidence uses captured Bearer and exact own active worker/company', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA); w.requests.clear();
    final evidence = await w.load(); addTearDown(evidence.dispose);
    expect(evidence.birthDate, '1980-01-15'); expect(evidence.canEdit, isTrue);
    expect(w.requests.map((r) => r.url.path), ['/rest/v1/company_members',
      '/rest/v1/workers', '/rest/v1/rpc/current_worker_personnel_profile']);
    expect(w.requests.every((r) => r.headers['Authorization'] == 'Bearer ${w.token(sidA)}'), isTrue);
    expect(w.requests[1].url.queryParameters, {'select': 'id', 'company_id': 'eq.$company',
      'user_id': 'eq.$actor', 'status': 'eq.active', 'limit': '2'});
  });
  test('explicit date goes through the existing canonical save and retains family data', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    final result = await w.save(evidence, '1981-03-04');
    expect(result['status'], 'saved'); expect(w.birthday, '1981-03-04');
    expect(w.writes.single['p_worker_id'], worker);
    expect((w.writes.single['p_payload'] as Map)['family_members'], family);
    expect((w.writes.single['p_payload'] as Map)['birth_date'], '1981-03-04');
    expect(w.requests.last.headers['Authorization'], 'Bearer ${w.token(sidA)}');
    expect(evidence.canEdit, isFalse);
  });
  test('omission preserves birthday with no implicit birthday read or write', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA); w.requests.clear();
    await w.repository.savePersonnelProfile(workerId: worker, payload: payload());
    expect(w.birthday, '1980-01-15');
    expect((w.writes.single['p_payload'] as Map).containsKey('birth_date'), isFalse);
    expect(w.requests.single.url.path, '/rest/v1/rpc/save_worker_personnel_profile');
  });
  test('fresh saved date conflict stops rather than choosing or overwriting a date', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    w.birthday = '1982-02-02';
    await expectLater(w.save(evidence, '1981-01-01'), throwsStateError);
    expect(w.birthday, '1982-02-02'); expect(w.writes, isEmpty);
    expect(evidence.canEdit, isFalse);
  });
  test('ambiguous membership, wrong worker and malformed contract fail before saving', () async {
    for (final change in <void Function(Wire)>[
      (w) => w.members = [...w.members, {'company_id': foreign, 'role': 'owner'}],
      (w) => w.workers = [{'id': foreign}],
      (w) => w.returnedWorker = foreign,
      (w) => w.contract = 1.0,
      (w) => w.birthday = '1980-02-30',
    ]) {
      final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA); change(w);
      await expectLater(w.load(), throwsStateError); expect(w.writes, isEmpty);
    }
  });
  test('invalid submitted dates never reach the writer', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    for (final date in <Object>['1980-02-30', '2099-01-01', '1899-12-31', 19800101]) {
      await expectLater(w.save(evidence, date), throwsStateError);
    }
    expect(w.writes, isEmpty);
  });
  test('old evidence cannot save after same-UID SID A B A', () async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    await w.login(sidB); await w.login(sidA);
    expect(w.client.auth.currentSession!.accessToken, w.token(sidA));
    await expectLater(w.save(evidence, '1981-01-01'), throwsStateError);
    expect(w.writes, isEmpty);
  });
  test('approval response is pending and does not pretend the official date changed', () async {
    final w = Wire()..pending = true; addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    final result = await w.save(evidence, '1981-01-01');
    expect(result['requires_approval'], isTrue); expect(w.birthday, '1980-01-15');
  });
  test('lost save response retires evidence and never blindly repeats the writer', () async {
    final w = Wire()..loseSaveAck = true; addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    await expectLater(w.save(evidence, '1981-01-01'), throwsA(isA<http.ClientException>()));
    expect(w.writes.length, 1); expect(w.birthday, '1981-01-01');
    await expectLater(w.save(evidence, '1981-01-01'), throwsStateError);
    expect(w.writes.length, 1);
  });
  test('malformed save response is unknown rather than reported as saved', () async {
    final w = Wire()..malformedSave = true; addTearDown(w.client.dispose); await w.login(sidA);
    final evidence = await w.load(); addTearDown(evidence.dispose);
    await expectLater(w.save(evidence, '1981-01-01'), throwsStateError);
    expect(evidence.canEdit, isFalse); expect(w.writes.length, 1);
  });
  testWidgets('old database shows disabled own birthday without disabling unrelated save', (tester) async {
    final w = Wire()..contract = null; addTearDown(w.client.dispose); await w.login(sidA);
    await showProfile(tester, w);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('profile-birthday-field')));
    expect(field.enabled, isFalse); expect(field.controller!.text, isEmpty);
    expect(find.text('生年月日の登録は準備中です。'), findsOneWidget);
    await saveProfile(tester);
    expect((w.writes.single['p_payload'] as Map).containsKey('birth_date'), isFalse);
  });
  testWidgets('unmodified profile UI omits own birthday even when contract is enabled', (tester) async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA);
    await showProfile(tester, w);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('profile-birthday-field')));
    expect(field.enabled, isTrue); expect(field.controller!.text, '1980-01-15');
    await saveProfile(tester);
    expect((w.writes.single['p_payload'] as Map).containsKey('birth_date'), isFalse);
    expect(w.birthday, '1980-01-15');
  });
  testWidgets('explicit clear in profile UI submits null and preserves family birthday', (tester) async {
    final w = Wire(); addTearDown(w.client.dispose); await w.login(sidA);
    await showProfile(tester, w);
    final clear = find.byKey(const ValueKey('profile-birthday-clear'));
    await tester.scrollUntilVisible(clear, 400, scrollable: find.byType(Scrollable).first);
    await tester.tap(clear); await tester.pumpAndSettle();
    await saveProfile(tester);
    expect((w.writes.single['p_payload'] as Map)['birth_date'], isNull);
    expect(((w.writes.single['p_payload'] as Map)['family_members'] as List).single['birth_date'], '2020-02-02');
  });
}
