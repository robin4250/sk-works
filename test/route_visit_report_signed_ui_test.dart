import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/route_visit_report_context.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  testWidgets('visit reporter signature freezes draft and reporter while responsibility remains available',
    (tester) => HttpOverrides.runWithHttpOverrides(() async {
      final requests = <String>[];
      late DailyReportRepository repository;
      late SupabaseClient client;
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          await request.drain<void>();
          requests.add(request.uri.path.split('/').last);
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'id': 'visit-report', 'source_clock_in_id': 'source',
            'route_assignment_id': 'route', 'route_stop_id': 'stop',
            'start_capture_id': 'arrival', 'end_capture_id': 'move',
            'site_id': 'site', 'site_name': '現場', 'report_date': '2026-10-11',
            'status': 'reporter_signed', 'work_description': '保存済み作業',
            'representative_signer_name': '保存済み報告者',
            'representative_signature_json': {'strokes': [[[1, 2], [3, 4]]]},
            'workers': [{'worker_id': 'worker', 'worker_name': 'メンバー'}],
          }));
          await request.response.close();
        });
        client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false));
        repository = DailyReportRepository.forTesting(client);
      });
      addTearDown(() async { await client.dispose(); await server.close(force: true); });
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(home: DailyReportPage(
          repositoryForTesting: repository,
          routeVisitContext: const RouteVisitReportContext(sourceClockInId: 'source',
            routeAssignmentId: 'route', routeStopId: 'stop',
            startCaptureId: 'arrival', endCaptureId: 'move'),
        )));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('保存済み作業'), findsOneWidget);
      for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(field.enabled, false);
      }
      await tester.scrollUntilVisible(find.text('報告者サイン'), 250);
      final reporter = tester.widget<ListTile>(find.ancestor(
        of: find.text('報告者サイン'), matching: find.byType(ListTile)));
      expect(reporter.onTap, null);
      await tester.scrollUntilVisible(find.text('責任者サイン'), 250);
      final responsible = tester.widget<ListTile>(find.ancestor(
        of: find.text('責任者サイン'), matching: find.byType(ListTile)));
      expect(responsible.onTap, isNotNull);
      expect(find.widgetWithText(FilledButton, '登録'), findsNothing);
      expect(requests, ['read_route_visit_report']);
    }, _RealHttpOverrides()));
}
