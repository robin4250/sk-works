import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/attendance/attendance_management_page.dart';
import 'package:sk_works/features/attendance/attendance_management_repository.dart';
import 'attendance_unrecorded_punches_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final invalid in [false, true]) {
    test('existing report read enforces server scope and returned membership invalid=$invalid', () async {
      final auth = fixture.Fixture();
      await auth.start();
      addTearDown(auth.client.dispose);
      final requests = <http.Request>[];
      final client = SupabaseClient('https://reports.invalid', 'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          Object body;
          if (request.url.path == '/auth/v1/token') {
            body = auth.client.auth.currentSession!.toJson();
          } else if (request.url.path.endsWith('/company_members')) {
            body = [{'company_id': fixture.company, 'role': 'owner'}];
          } else if (request.url.path.endsWith('/current_feature_permissions')) {
            body = {'can_manage_attendance': true};
          } else if (request.url.path.endsWith('/daily_reports')) {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['company_id'], 'eq.${fixture.company}');
            expect(request.url.queryParameters['report_date'], 'eq.2026-10-25');
            expect(request.url.queryParameters['daily_report_workers.worker_id'], 'eq.${fixture.worker}');
            body = [{'id': fixture.site, 'company_id': fixture.company,
              'report_date': '2026-10-25', 'site_id': fixture.site,
              'route_assignment_id': null, 'daily_report_workers': [
                {'worker_id': invalid ? fixture.actor : fixture.worker}]}];
          } else if (request.url.path.endsWith('/attendance_entries') ||
              request.url.path.endsWith('/paid_leave_requests') ||
              request.url.path.endsWith('/attendance_verifications')) {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['company_id'], 'eq.${fixture.company}');
            expect(request.url.queryParameters['worker_id'], 'eq.${fixture.worker}');
            if (request.url.path.endsWith('/attendance_entries')) {
              body = [{'work_date': '2026-10-25'}];
            } else if (request.url.path.endsWith('/paid_leave_requests')) {
              expect(request.url.queryParameters['status'], 'eq.approved');
              body = [{'leave_date': '2026-10-27'}];
            } else {
              body = [{'work_date': '2026-10-25', 'event_type': 'clock_in'},
                {'work_date': '2026-10-26', 'event_type': 'clock_out'}];
            }
          } else {
            throw StateError('Unexpected request ${request.url.path}');
          }
          return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'}, request: request);
        }));
      addTearDown(client.dispose);
      // Reuse the established synthetic authentication fixture, no real auth.
      await client.auth.signInWithPassword(email: 'fixture@example.invalid', password: 'synthetic');
      requests.clear();
      final result = AttendanceManagementRepository.forTesting(client).loadReports(
        workerId: fixture.worker, date: DateTime(2026, 10, 25));
      if (invalid) {
        await expectLater(result, throwsStateError);
      } else {
        final reports = await result;
        expect(reports.single.id, fixture.site);
        expect(reports.single.date, DateTime(2026, 10, 25));
      }
      expect(requests.where((r) => r.method != 'GET' &&
        !r.url.path.endsWith('/current_feature_permissions')), isEmpty);
      expect(requests.where((r) => r.url.path.endsWith('/current_feature_permissions')), hasLength(2));
      final marks = await AttendanceManagementRepository.forTesting(client).loadMonthMarks(
        workerId: fixture.worker, month: DateTime(2026, 10));
      expect(marks[25], {'work'});
      expect(marks[26], {'punch'});
      expect(marks[27], {'leave'});
    });
  }
  testWidgets('management exposes saved report recovery before editing fields', (tester) async {
    final f = fixture.Fixture();
    await tester.runAsync(f.start);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.client.dispose);
    });
    await tester.runAsync(() => tester.pumpWidget(MaterialApp(home: AttendanceManagementPage(
      repository: fixture.PageFixture(f.client), initialWorkerId: fixture.worker,
      initialDate: DateTime(2026, 10, 25), restrictedRecovery: true))));
    await tester.pumpAndSettle();
    expect(find.text('この日の日報・共通手当・サインを開く'), findsOneWidget);
    expect(find.textContaining('署名済み内容は保持'), findsOneWidget);
    expect(f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance')), isEmpty);
  });
  testWidgets('calendar distinguishes authoritative work, pending punches and approved leave', (tester) async {
    final f = fixture.Fixture();
    await tester.runAsync(f.start);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.client.dispose);
    });
    final semantics = tester.ensureSemantics();
    try {
      final repository = _CalendarFixture(f.client);
      await tester.pumpWidget(MaterialApp(home: AttendanceManagementPage(
        repository: repository, initialWorkerId: fixture.worker,
        initialDate: DateTime(2026, 10, 25))));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '2026/10/25'));
      await tester.pumpAndSettle();
      expect(repository.worker, fixture.worker);
      expect(find.bySemanticsLabel(RegExp(r'10月25日 出勤')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'10月26日 打刻のみ')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'10月27日 承認済み有給')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp(r'10月26日 打刻のみ')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, '2026/10/26'), findsOneWidget);
      expect(f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance')), isEmpty);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('leaving management releases the focused input', (tester) async {
    final f = fixture.Fixture();
    await tester.runAsync(f.start);
    final repository = fixture.PageFixture(f.client)
      ..onLoad = (worker, date) async => AttendanceManagementCell(
        mode: 'work', workerId: worker, date: date, siteId: fixture.site);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.client.dispose);
    });
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.push<void>(context,
        MaterialPageRoute(builder: (_) => AttendanceManagementPage(repository: repository))),
        child: const Text('管理を開く'))))));
    await tester.tap(find.text('管理を開く'));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, '人工');
    final vertical = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(input, 180, scrollable: vertical.first);
    await tester.showKeyboard(input);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('管理を開く'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}

class _CalendarFixture extends fixture.PageFixture {
  _CalendarFixture(super.client);
  String? worker;
  @override Future<Map<int, Set<String>>> loadMonthMarks({required String workerId,
      required DateTime month}) async {
    worker = workerId;
    return {25: {'work'}, 26: {'punch'}, 27: {'leave'}};
  }
}
