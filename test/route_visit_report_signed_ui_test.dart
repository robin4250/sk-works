// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_page.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/route_visit_report_context.dart';

class _RealHttpOverrides extends HttpOverrides {}

const _visitContext = RouteVisitReportContext(sourceClockInId: 'source',
  routeAssignmentId: 'route', routeStopId: 'stop', startCaptureId: 'arrival', endCaptureId: 'move');
class _VisitFinalizationFixture implements DailyReportRepository {
  bool finalized = false, loseAcknowledgement = false;
  int finalizationWrites = 0;
  @override String? get currentActorId => 'actor';
  @override Future<DailyReportRecord?> loadVisitReport(RouteVisitReportContext context) async =>
    DailyReportRecord(id: 'visit-report', companyId: 'company', siteId: 'site', routeAssignmentId: 'route',
      siteName: '現場', date: DateTime(2026, 10, 26), workDescription: '保存済みの訪問作業',
      status: finalized ? 'signed' : 'reporter_signed',
      workers: [DailyReportWorkerDraft(workerId: 'worker', workerName: '現場メンバー')],
      reporterSignerName: '報告者', reporterSignatureJson: {'strokes': [[{'x': 0.1, 'y': 0.2}, {'x': 0.3, 'y': 0.4}]]},
      responsibleSignerName: '責任者', responsibleSignatureJson: {'strokes': [[{'x': 0.2, 'y': 0.3}, {'x': 0.4, 'y': 0.5}]]},
      visitFinalizationRequired: true, visitFinalizationReady: !finalized,
      visitFinalizationCompleted: finalized, visitExpectedUpdatedAt: DateTime.utc(2026, 10, 26),
      visitSignatureScope: List.filled(64, 'a').join());
  @override Future<DailyReportRecord> finalizeVisit({required RouteVisitReportContext context,
    required DailyReportRecord before}) async {
    expect(before.canFinalizeVisit, isTrue); finalizationWrites++; finalized = true;
    if (loseAcknowledgement) throw StateError('確定結果を受信できませんでした。');
    return (await loadVisitReport(context))!;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  });
  for (final loseAcknowledgement in [false, true]) {
    testWidgets('visit signatures do not finalize before step five; lost ACK=$loseAcknowledgement', (tester) async {
      final repository = _VisitFinalizationFixture()..loseAcknowledgement = loseAcknowledgement;
      await tester.pumpWidget(MaterialApp(home: DailyReportPage(repositoryForTesting: repository,
        routeVisitContext: _visitContext)));
      await tester.pumpAndSettle();
      expect(repository.finalized, isFalse); expect(repository.finalizationWrites, 0);
      final button = find.byKey(const ValueKey('daily-report-finalize'));
      await tester.scrollUntilVisible(button, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(button); await tester.pumpAndSettle();
      await tester.tap(button); await tester.pumpAndSettle();
      expect(repository.finalized, isTrue); expect(repository.finalizationWrites, 1);
      expect(find.byKey(const ValueKey('daily-report-finalize')), findsNothing);
    });
  }
  testWidgets(
    'visit reporter signature freezes draft and reporter while responsibility remains available',
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
          request.response.write(
            jsonEncode({
              'id': 'visit-report',
              'source_clock_in_id': 'source',
              'route_assignment_id': 'route',
              'route_stop_id': 'stop',
              'start_capture_id': 'arrival',
              'end_capture_id': 'move',
              'site_id': 'site',
              'site_name': '現場',
              'report_date': '2026-10-11',
              'status': 'reporter_signed',
              'work_description': '保存済み作業',
              'representative_signer_name': '保存済み報告者',
              'representative_signature_json': {
                'strokes': [
                  [
                    {'x': 0.1, 'y': 0.2},
                    {'x': 0.3, 'y': 0.4},
                  ],
                ],
              },
              'workers': [
                {'worker_id': 'worker', 'worker_name': 'メンバー'},
              ],
            }),
          );
          await request.response.close();
        });
        client = SupabaseClient(
          'http://127.0.0.1:${server.port}',
          'synthetic-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        repository = DailyReportRepository.forTesting(client);
      });
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: DailyReportPage(
              repositoryForTesting: repository,
              routeVisitContext: const RouteVisitReportContext(
                sourceClockInId: 'source',
                routeAssignmentId: 'route',
                routeStopId: 'stop',
                startCaptureId: 'arrival',
                endCaptureId: 'move',
              ),
            ),
          ),
        );
        final deadline = Stopwatch()..start();
        while (find.text('保存済み作業').evaluate().isEmpty) {
          if (deadline.elapsed > const Duration(seconds: 5)) {
            fail('訪問日報の読込が完了しませんでした');
          }
          await Future<void>.delayed(Duration.zero);
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('保存済み作業'), findsOneWidget);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.enabled, false);
      }
      final reportScrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('報告者サイン'),
        250,
        scrollable: reportScrollable,
      );
      final reporter = tester.widget<ListTile>(
        find.ancestor(of: find.text('報告者サイン'), matching: find.byType(ListTile)),
      );
      expect(reporter.onTap, null);
      await tester.scrollUntilVisible(
        find.text('責任者サイン'),
        250,
        scrollable: reportScrollable,
      );
      final responsible = tester.widget<ListTile>(
        find.ancestor(of: find.text('責任者サイン'), matching: find.byType(ListTile)),
      );
      expect(responsible.onTap, isNotNull);
      expect(find.widgetWithText(FilledButton, '登録'), findsNothing);
      expect(requests, ['read_route_visit_report']);
    }, _RealHttpOverrides()),
  );
}

