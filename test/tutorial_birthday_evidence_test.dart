import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/tutorial/tutorial_evidence_repository.dart';
import 'tutorial_evidence_repository_test.dart' show FixtureSource;

const worker = '10000000-0000-0000-0000-000000000003';

Future<TutorialEvidenceCheckpoint> birthday(Map<String, dynamic> row) async {
  final source = FixtureSource()..personnelRow = row;
  final snapshot = await TutorialEvidenceRepository(source)
      .load(availableActionKeys: {'profile'});
  final task = snapshot.tasks.singleWhere(
    (task) => task.key == 'personnel_details_recommended',
  );
  expect(task.requiredForCompletion, isFalse);
  return task.checkpoints.singleWhere((item) => item.key == 'birth_date');
}

Map<String, dynamic> official(Object? value, {Object? version = 1}) => {
  'worker_id': worker,
  'name': 'Synthetic',
  'birth_date_contract_version': version,
  'birth_date': value,
  'personnel_cas_digest': '0123456789abcdef0123456789abcdef',
};


const actor = '10000000-0000-0000-0000-000000000001';
const company = '10000000-0000-0000-0000-000000000002';
const sid = '10000000-0000-0000-0000-000000000004';
class BirthdayWire {
  Object? returnedWorker = worker;
  int workerCount = 1;
  final requests = <http.Request>[];
  final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  late final client = SupabaseClient('https://synthetic.invalid', 'synthetic-public',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(respond));
  String token() {
    String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'sub': actor, 'role': 'authenticated', 'session_id': sid, 'exp': expiry})}.synthetic';
  }
  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    final Object? value;
    switch (request.url.path) {
      case '/auth/v1/token':
        value = {'access_token': token(), 'refresh_token': 'synthetic',
          'expires_in': 3600, 'token_type': 'bearer',
          'user': {'id': actor, 'aud': 'authenticated', 'role': 'authenticated',
            'email': 'synthetic@example.invalid', 'app_metadata': {},
            'user_metadata': {}, 'created_at': '2026-10-31T00:00:00Z'}};
      case '/rest/v1/company_members':
        value = [{'company_id': company, 'role': 'employee'}];
      case '/rest/v1/user_profiles':
        value = {'user_id': actor, 'display_name': 'Synthetic', 'phone': 'synthetic'};
      case '/rest/v1/workers':
        value = List.generate(workerCount, (_) => {'id': worker});
      case '/rest/v1/rpc/current_worker_personnel_profile':
        value = {...official('1980-02-29', version: 2), 'worker_id': returnedWorker};
      default:
        throw StateError('Unexpected path ${request.url.path}');
    }
    return http.Response(jsonEncode(value), 200,
      headers: {'content-type': 'application/json'}, request: request);
  }
  Future<TutorialEvidenceCheckpoint> load() async {
    await client.auth.signInWithPassword(email: 'synthetic@example.invalid', password: 'synthetic');
    await Future<void>.delayed(Duration.zero);
    requests.clear();
    final snapshot = await TutorialEvidenceRepository.forClient(client, companyId: company)
      .load(availableActionKeys: {'profile'});
    return snapshot.tasks.singleWhere((task) => task.key == 'personnel_details_recommended')
      .checkpoints.singleWhere((item) => item.key == 'birth_date');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real SDK binds official DOB to selected company and own worker', () async {
    final wire = BirthdayWire();
    addTearDown(wire.client.dispose);
    expect((await wire.load()).state, TutorialEvidenceState.saved);
    final rpc = wire.requests.where((r) => r.method == 'POST').toList();
    expect(rpc.map((r) => r.url.path), ['/rest/v1/rpc/current_worker_personnel_profile']);
    expect(wire.requests.every((r) => r.headers['Authorization'] == 'Bearer ${wire.token()}'), isTrue);
    final own = wire.requests.singleWhere((r) => r.url.path == '/rest/v1/workers');
    expect(own.url.queryParameters['company_id'], 'eq.$company');
    expect(own.url.queryParameters['user_id'], 'eq.$actor');
  });
  test('real SDK foreign or ambiguous worker cannot count saved DOB', () async {
    for (final count in [0, 2]) {
      final wire = BirthdayWire()..workerCount = count;
      addTearDown(wire.client.dispose);
      expect((await wire.load()).state, TutorialEvidenceState.unknown);
      expect(wire.requests.where((r) => r.url.path.endsWith('current_worker_personnel_profile')), isEmpty);
    }
    final wire = BirthdayWire()..returnedWorker = actor;
    addTearDown(wire.client.dispose);
    expect((await wire.load()).state, TutorialEvidenceState.unknown);
  });
  for (final version in [1, 2]) {
    test('contract $version official value is saved independently of writability', () async {
      final result = await birthday(official('1980-02-29', version: version));
      expect(result.state, TutorialEvidenceState.saved);
      expect(result.evidenceKey, '$worker:birth_date');
    });
    for (final empty in [null, '']) {
      test('contract $version empty $empty is missing not unknown', () async {
        final result = await birthday(official(empty, version: version));
        expect(result.state, TutorialEvidenceState.missing);
        expect(result.statusLabel, '未設定');
      });
    }
  }
  test('unknown contract never claims saved', () async {
    for (final version in [null, 0, 3, '2', 2.0, true]) {
      expect((await birthday(official('1980-01-01', version: version))).state,
        TutorialEvidenceState.unknown);
    }
  });
  test('malformed dates and non-string values are unknown', () async {
    for (final value in [true, 19800101, <String, dynamic>{},
      '1980-02-30', '1981-02-29', '1980-1-01', ' 1980-01-01',
      '1980-01-01 ', '1800-01-01', '9999-01-01', ' ']) {
      expect((await birthday(official(value))).state,
        TutorialEvidenceState.unknown, reason: '$value');
    }
  });
  test('missing official field never substitutes a pending proposal', () async {
    final row = official(null)..remove('birth_date');
    row['proposed_payload'] = {'birth_date': '1980-01-01'};
    expect((await birthday(row)).state, TutorialEvidenceState.unknown);
    row['birth_date'] = null;
    expect((await birthday(row)).state, TutorialEvidenceState.missing);
  });
  test('worker receipt and v2 digest must be well formed', () async {
    for (final value in [null, 'w1', 3]) {
      expect((await birthday(official('1980-01-01')..['worker_id'] = value)).state,
        TutorialEvidenceState.unknown);
    }
    for (final value in [null, '', 'bad', 3]) {
      expect((await birthday(official('1980-01-01', version: 2)
        ..['personnel_cas_digest'] = value)).state,
        TutorialEvidenceState.unknown);
    }
  });
  test('optional DOB does not change required completion evidence', () async {
    List<TutorialEvidenceState>? baseline;
    for (final row in [official('1980-01-01'), official(null),
      official('bad'), official('1980-01-01', version: 3)]) {
      final source = FixtureSource()..personnelRow = row;
      final snapshot = await TutorialEvidenceRepository(source)
          .load(availableActionKeys: {'profile'});
      final required = snapshot.tasks.where((task) => task.requiredForCompletion)
          .expand((task) => task.checkpoints).map((item) => item.state).toList();
      baseline ??= required;
      expect(required, baseline);
    }
  });
}
