import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_management_company_allowances.dart';
import 'package:sk_works/features/attendance/attendance_management_company_allowance_field.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';

const company = '00000000-0000-0000-0000-000000000001';
const first = '00000000-0000-0000-0000-000000000011';
const second = '00000000-0000-0000-0000-000000000012';
const item1 = '00000000-0000-0000-0000-000000000021';
const item2 = '00000000-0000-0000-0000-000000000022';
const item3 = '00000000-0000-0000-0000-000000000023';

Map<String, Object?> label(String id, String name, String unit) => {
  'origin': 'company_common', 'id': id, 'name': name, 'unit': unit,
  'generation': null, 'registration_version': 4, 'legacy_slot': null,
  'payroll_type': 'daily', 'section': 'earning', 'display_unit': unit,
};
Map<String, Object?> identity(String id) => {'origin': 'company_common', 'id': id,
  'generation': null, 'registration_version': 4};
Map<String, dynamic> response({bool bulk = false, String worker = first}) => {
  'contract_version': 1, 'company_id': company,
  'labels': {'contract_version': 1, 'company_id': company, 'registration_scope': 'current',
    'source_versions': {'common_version': 4, 'legacy_version': null},
    'items': [label(item1, '鉄骨', 'day'), label(item2, '時間手当', 'hour'), label(item3, '月手当', 'month')]},
  'workers': [
    {'worker_id': worker, 'items': [identity(item1), identity(item2)]},
    if (bulk) {'worker_id': second, 'items': [identity(item2)]},
  ],
};

class FixtureRepository extends AttendanceManagementRepository {
  FixtureRepository(this.client, this.read) : super.forTesting(client);
  final SupabaseClient client;
  final Future<AttendanceManagementAllowanceOptions> Function(List<String>) read;
  @override
  Future<AttendanceManagementAllowanceOptions> loadCompanyAllowanceOptions(Iterable<String> workerIds) => read(workerIds.toList());
}

void main() {
  test('catalog rejects A to B to A auth history even with the original token restored', () async {
    const actor = '00000000-0000-0000-0000-000000000041';
    const other = '00000000-0000-0000-0000-000000000042';
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    var user = actor;
    var switchDuringRead = false;
    late SupabaseClient client;
    Future<void> login(String id) async {
      user = id;
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'fixture-only');
      await Future<void>.delayed(Duration.zero);
    }
    client = SupabaseClient('https://synthetic.invalid', 'fixture-only',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        Object? body;
        switch (request.url.path) {
          case '/auth/v1/token':
            String enc(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
            body = {
              'access_token': '${enc({'alg': 'HS256'})}.${enc({'sub': user, 'role': 'authenticated', 'session_id': user, 'exp': expiry})}.fixture',
              'refresh_token': 'fixture-only', 'token_type': 'bearer', 'expires_in': 3600,
              'user': {'id': user, 'aud': 'authenticated', 'role': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'},
            };
            break;
          case '/rest/v1/company_members':
            body = [{'company_id': company, 'role': 'owner'}];
            break;
          case '/rest/v1/rpc/current_feature_permissions':
            body = {'can_manage_attendance': true};
            break;
          case '/rest/v1/rpc/read_management_company_allowance_options':
            if (switchDuringRead) {
              switchDuringRead = false;
              await login(other);
              await login(actor);
            }
            body = response();
            break;
          default:
            throw StateError('Unexpected fixture path');
        }
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    addTearDown(client.dispose);
    await login(actor);
    final repository = AttendanceManagementRepository.forTesting(client);
    expect((await repository.loadCompanyAllowanceOptions([first])).labels.companyId, company);
    final original = client.auth.currentSession!.accessToken;
    switchDuringRead = true;
    await expectLater(repository.loadCompanyAllowanceOptions([first]), throwsStateError);
    expect(client.auth.currentSession!.accessToken, original);
  });

  test('bulk selection uses the intersection without changing registered identities', () {
    final value = AttendanceManagementAllowanceOptions.parse(response(bulk: true), companyId: company, workerIds: [first, second]);
    expect(value.sharedEligibleKeys, {'company_common/$item2'});
    expect(value.labels.items.map((item) => item.name), ['鉄骨', '時間手当', '月手当']);
    expect(() => value.workers[first]!.clear(), throwsUnsupportedError);
  });

  for (final kind in ['foreign', 'missing-worker', 'duplicate-worker', 'stale-version', 'unknown-id', 'monthly-eligible']) {
    test('rejects an unbound management allowance response: $kind', () {
      final raw = response();
      final workers = raw['workers'] as List;
      final worker = workers.first as Map;
      final items = worker['items'] as List;
      switch (kind) {
        case 'foreign': raw['company_id'] = second; break;
        case 'missing-worker': workers.clear(); break;
        case 'duplicate-worker': workers.add(worker); break;
        case 'stale-version': (items.first as Map)['registration_version'] = 3; break;
        case 'unknown-id': (items.first as Map)['id'] = first; break;
        case 'monthly-eligible': items.add(identity(item3)); break;
      }
      expect(() => AttendanceManagementAllowanceOptions.parse(raw, companyId: company, workerIds: [first]), throwsFormatException);
    });
  }

  test('registered identity metadata is sent separately from free names; untouched fields are omitted', () async {
    final payloads = <Map<String, dynamic>>[];
    final client = SupabaseClient('https://synthetic.invalid', 'fixture-only',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('1', 200, headers: {'content-type': 'application/json'}, request: request);
      }));
    addTearDown(client.dispose);
    final repository = AttendanceManagementRepository.forTesting(client);
    await repository.apply(action: 'upsert', workerIds: [first], dates: [DateTime(2026, 10, 20)], mode: 'work');
    final untouched = (payloads.first['p_items'] as List).single as Map;
    expect(untouched.containsKey('company_allowance_selections'), isFalse);
    expect(untouched.containsKey('company_allowance_legacy_labels'), isFalse);
    final options = AttendanceManagementAllowanceOptions.parse(response(), companyId: company, workerIds: [first]);
    final selected = DailyReportCompanyAllowanceSelections([DailyReportCompanyAllowanceSelection.registered(options.labels.items.first)]);
    await repository.apply(action: 'upsert', workerIds: [first], dates: [DateTime(2026, 10, 20)], mode: 'work',
      allowanceNames: ['自由手当'], companyAllowanceSelections: selected, companyAllowanceLegacyLabels: '自由手当');
    final saved = (payloads.last['p_items'] as List).single as Map;
    expect(saved['company_allowance_selections'], selected.toJson());
    expect(saved['allowance_names'], ['自由手当']);
    expect(saved['company_allowance_legacy_labels'], '自由手当');
  });

  testWidgets('a late old-worker catalog cannot replace the selected worker catalog', (tester) async {
    final client = (await tester.runAsync(() async {
      final value = SupabaseClient('https://synthetic.invalid', 'fixture-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
      // Initialize SDK lifecycle timers on the real clock, as the page fixtures do.
      await Future<void>.delayed(Duration.zero);
      return value;
    }))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    });
    final a = Completer<AttendanceManagementAllowanceOptions>();
    final b = Completer<AttendanceManagementAllowanceOptions>();
    final repository = FixtureRepository(client, (ids) => ids.single == first ? a.future : b.future);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Widget page(String worker) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      AttendanceManagementCompanyAllowanceField(repository: repository, workerIds: [worker], controller: controller,
        selections: null, onChanged: (_) {}, onReady: (_) {}, enabled: true))));
    await tester.pumpWidget(page(first));
    await tester.pumpWidget(page(second));
    b.complete(AttendanceManagementAllowanceOptions.parse(response(worker: second), companyId: company, workerIds: [second]));
    await tester.pump();
    a.completeError(StateError('old account response'));
    await tester.pump();
    expect(find.text('鉄骨'), findsOneWidget);
    expect(find.text('共通手当を再読み込み'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
