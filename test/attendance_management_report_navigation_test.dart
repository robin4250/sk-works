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
    expect(find.text('この日の日報・サインを開く'), findsOneWidget);
    expect(find.textContaining('署名済み内容は保持'), findsOneWidget);
    expect(f.calls.where((r) => r.url.path.endsWith('/force_manage_attendance')), isEmpty);
  });
}
