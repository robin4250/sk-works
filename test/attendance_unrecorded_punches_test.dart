import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'package:sk_works/features/attendance/attendance_management_company_allowances.dart';

const actor = '11111111-1111-1111-1111-111111111111';
const company = '22222222-2222-2222-2222-222222222222';
const worker = '33333333-3333-3333-3333-333333333333';
const site = '44444444-4444-4444-4444-444444444444';

class Fixture {
  final calls = <http.Request>[];
  bool recorded = false;
  bool leave = false;
  bool allowed = true;
  List<Map<String, dynamic>> punches = [
    {
      'event_type': 'clock_in',
      'confirmed_at': '2026-10-13T08:13:00Z',
      'site_id': site,
    },
    {
      'event_type': 'clock_out',
      'confirmed_at': '2026-10-13T17:21:00Z',
      'site_id': site,
    },
  ];
  late SupabaseClient client;
  late AttendanceManagementRepository repository;
  Future<void> start() async {
    client = SupabaseClient(
      'https://attendance-fixture.invalid',
      'synthetic',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        Object? body;
        switch (request.url.path) {
          case '/auth/v1/token':
            String enc(Object value) => base64Url
                .encode(utf8.encode(jsonEncode(value)))
                .replaceAll('=', '');
            body = {
              'access_token':
                  '${enc({'alg': 'HS256'})}.${enc({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.c3ludGhldGlj',
              'refresh_token': 'synthetic',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': actor,
                'aud': 'authenticated',
                'role': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
              },
            };
          case '/rest/v1/company_members':
            body = [
              {'company_id': company, 'role': 'owner'},
            ];
          case '/rest/v1/rpc/current_feature_permissions':
            body = {'can_manage_attendance': allowed};
          case '/rest/v1/workers':
            body = [
              {'id': worker, 'name': '検証社員'},
            ];
          case '/rest/v1/sites':
            body = [
              {'id': site, 'name': '検証現場'},
            ];
          case '/rest/v1/rpc/force_manage_attendance':
            body = 1;
          case '/rest/v1/attendance_entries':
            body = recorded
                ? [
                    {'id': 'entry', 'site_id': site, 'base_man_days': 1},
                  ]
                : [];
          case '/rest/v1/paid_leave_requests':
            body = leave
                ? [
                    {'reason': '承認済み'},
                  ]
                : [];
          case '/rest/v1/attendance_verifications':
            body = punches;
          default:
            throw StateError(
              'Unexpected ${request.method} ${request.url.path}',
            );
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'synthetic',
    );
    calls.clear();
    repository = AttendanceManagementRepository.forTesting(client);
  }
}

class PageFixture extends AttendanceManagementRepository {
  PageFixture(super.client) : super.forTesting();
  Future<AttendanceManagementCell> Function(String, DateTime)? onLoad;
  // This fixture isolates attendance/time edits with the allowance rollout OFF.
  // Registered-choice loading and failures have their own focused widget tests.
  @override
  Future<AttendanceManagementAllowanceOptions> loadCompanyAllowanceOptions(
    Iterable<String> workerIds,
  ) async => throw StateError('共通手当は準備中です。');

  @override
  Future<AttendanceManagementSavedAllowances> loadSavedCompanyAllowances({
    required String workerId, required DateTime date,
    String? reportId, String? siteId,
  }) async => const AttendanceManagementSavedAllowances();

  @override
  Future<
    ({
      List<AttendanceManagementOption> workers,
      List<AttendanceManagementOption> sites,
    })
  >
  loadOptions() async => (
    workers: const [
      AttendanceManagementOption(id: worker, name: '検証社員'),
      AttendanceManagementOption(id: actor, name: '別社員'),
    ],
    sites: const [AttendanceManagementOption(id: site, name: '検証現場')],
  );
  @override
  Future<AttendanceManagementCell> loadCell({
    required String workerId,
    required DateTime date,
  }) async => onLoad != null
      ? await onLoad!(workerId, date)
      : AttendanceManagementCell(
          mode: 'pending_work',
          date: date,
          workerId: workerId,
          siteId: site,
          manDays: 0,
          hasUnrecordedPunches: true,
          clockIn: DateTime(2026, 10, 13, 8, 13),
          clockOut: DateTime(2026, 10, 13, 17, 21),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'two recorded days and one punch-only day remain distinguishable with no invented quantity or writes',
    () async {
      final f = Fixture();
      await f.start();
      addTearDown(f.client.dispose);
      final cells = <AttendanceManagementCell>[];
      for (final day in [12, 13, 16]) {
        f.recorded = day != 13;
        cells.add(
          await f.repository.loadCell(
            workerId: worker,
            date: DateTime(2026, 10, day),
          ),
        );
      }
      expect(cells.where((cell) => cell.mode == 'work'), hasLength(2));
      final missing = cells[1];
      expect(missing.hasUnrecordedPunches, true);
      expect(missing.manDays, 0);
      expect(missing.siteId, site);
      expect(missing.clockIn!.toUtc(), DateTime.utc(2026, 10, 13, 8, 13));
      expect(missing.clockOut!.toUtc(), DateTime.utc(2026, 10, 13, 17, 21));
      for (final call in f.calls.where(
        (r) => r.url.path == '/rest/v1/attendance_verifications',
      )) {
        expect(call.url.queryParameters['company_id'], 'eq.$company');
        expect(call.url.queryParameters['worker_id'], 'eq.$worker');
      }
      expect(
        f.calls.where(
          (r) =>
              r.method != 'GET' &&
              r.url.path != '/rest/v1/rpc/current_feature_permissions',
        ),
        isEmpty,
      );
    },
  );
  test(
    'approved leave, truly empty day, mixed sites and unauthorized reads are kept separate',
    () async {
      final f = Fixture();
      await f.start();
      addTearDown(f.client.dispose);
      f.leave = true;
      expect(
        (await f.repository.loadCell(
          workerId: worker,
          date: DateTime(2026, 10, 13),
        )).mode,
        'paid_leave',
      );
      f.leave = false;
      f.punches = [];
      expect(
        (await f.repository.loadCell(
          workerId: worker,
          date: DateTime(2026, 10, 13),
        )).hasUnrecordedPunches,
        false,
      );
      f.punches = [
        {
          'event_type': 'clock_in',
          'confirmed_at': '2026-10-13T08:13:00Z',
          'site_id': site,
        },
        {
          'event_type': 'clock_out',
          'confirmed_at': '2026-10-13T17:21:00Z',
          'site_id': worker,
        },
      ];
      expect(
        (await f.repository.loadCell(
          workerId: worker,
          date: DateTime(2026, 10, 13),
        )).siteId,
        isNull,
      );
      f.allowed = false;
      f.calls.clear();
      await expectLater(
        f.repository.loadCell(workerId: worker, date: DateTime(2026, 10, 13)),
        throwsStateError,
      );
      expect(
        f.calls.where((r) => r.url.path == '/rest/v1/attendance_entries'),
        isEmpty,
      );
    },
  );
  testWidgets(
    'punch-only day explains missing payroll source and refuses off-mode upsert',
    (tester) async {
      final f = Fixture();
      await tester.runAsync(f.start);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await f.client.dispose();
      });
      await tester.runAsync(
        () => tester.pumpWidget(
          MaterialApp(
            home: AttendanceManagementPage(repository: PageFixture(f.client)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('給与用の勤務記録は未確定'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, '登録・編集を直接反映');
      await tester.scrollUntilVisible(save, 180,
        scrollable: find.descendant(of: find.byType(ListView).first,
          matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('勤務内容を確認して出勤として登録'), findsOneWidget);
      expect(
        f.calls.where(
          (r) => r.url.path == '/rest/v1/rpc/force_manage_attendance',
        ),
        isEmpty,
      );
    },
  );
  testWidgets('late first-worker read cannot overwrite the selected worker', (
    tester,
  ) async {
    final fixture = Fixture();
    await tester.runAsync(fixture.start);
    final client = fixture.client;
    final repository = PageFixture(client);
    final old = Completer<AttendanceManagementCell>();
    final current = Completer<AttendanceManagementCell>();
    repository.onLoad = (id, date) =>
        id == worker ? old.future : current.future;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(client.dispose);
    });
    await tester.pumpWidget(
      MaterialApp(home: AttendanceManagementPage(repository: repository)),
    );
    await tester.pump();
    await tester.pump();
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    dropdown.onChanged!(actor);
    await tester.pump();
    current.complete(
      AttendanceManagementCell(
        mode: 'pending_work',
        date: DateTime.now(),
        workerId: actor,
        hasUnrecordedPunches: true,
        clockIn: DateTime(2026, 10, 13, 10, 4),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('出勤：10:04'), findsOneWidget);
    old.complete(
      AttendanceManagementCell(
        mode: 'pending_work',
        date: DateTime.now(),
        workerId: worker,
        hasUnrecordedPunches: true,
        clockIn: DateTime(2026, 10, 13, 8, 13),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('出勤：10:04'), findsOneWidget);
    expect(find.textContaining('出勤：08:13'), findsNothing);
  });
}
