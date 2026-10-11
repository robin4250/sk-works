import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/route_visit_report_context.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const context = RouteVisitReportContext(sourceClockInId: 'source',
    routeAssignmentId: 'route', routeStopId: 'stop',
    startCaptureId: 'arrival', endCaptureId: 'move');
  test('visit draft and signatures use isolated RPCs and preserve immutable visit identity',
    () => HttpOverrides.runWithHttpOverrides(() async {
      final requests = <String>[];
      var mismatch = false;
      var saveOverrides = <String, Object?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final rpc = request.uri.path.split('/').last;
        requests.add(rpc);
        if (rpc == 'save_route_visit_report_signature') {
          expect(body['p_report_id'], 'visit-report');
          expect(body['p_role'], anyOf('reporter', 'responsible'));
          expect(body['p_signature_json'], {'strokes': [[1, 2]]});
        } else {
          expect(body['p_start_capture_id'], 'arrival');
          expect(body['p_end_capture_id'], 'move');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'id': 'visit-report', 'source_clock_in_id': 'source',
          'route_assignment_id': 'route', 'route_stop_id': 'stop',
          'start_capture_id': 'arrival', 'end_capture_id': mismatch ? 'another-move' : 'move',
          'site_id': 'site', 'site_name': '現場', 'report_date': '2026-10-11',
          'status': rpc == 'save_route_visit_report_draft' ? 'draft' : 'completed', 'work_description': '作業',
          'representative_signer_name': '報告者',
          'supervisor_signer_name': '責任者',
          'workers': [{'worker_id': 'worker', 'worker_name': 'メンバー'}],
          if (rpc == 'save_route_visit_report_draft') ...saveOverrides,
        }));
        await request.response.close();
      });
      final client = SupabaseClient('http://127.0.0.1:${server.port}', 'synthetic-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
      addTearDown(() async { await client.dispose(); await server.close(force: true); });
      final repository = DailyReportRepository.forTesting(client);
      final report = await repository.loadVisitReport(context);
      expect(report!.signed, true);
      expect(report.workers.single.workerName, 'メンバー');
      expect(report.notificationRetryScope, null);
      expect(await repository.saveVisitDraft(context: context,
        workDescription: '作業', workers: report.workers), 'visit-report');
      for (final role in ['reporter', 'responsible']) {
        await repository.signVisit(reportId: report.id, role: role,
          signerName: '選択名', signatureJson: [[1, 2]]);
      }
      for (final invalid in <Map<String, Object?>>[
        {'status': 'reporter_signed'}, {'status': 'completed'}, {'id': ''},
        {'id': 'another-report'}, {'workers': []},
        {'workers': [{'worker_id': 'worker', 'overtime_hours': 2}]},
        {'work_description': '古い内容'},
      ]) {
        saveOverrides = invalid;
        await expectLater(repository.saveVisitDraft(context: context,
          expectedReportId: report.id, workDescription: '作業', workers: report.workers),
          throwsStateError);
      }
      mismatch = true;
      await expectLater(repository.loadVisitReport(context), throwsStateError);
      expect(requests, ['read_route_visit_report', 'save_route_visit_report_draft',
        'save_route_visit_report_signature', 'save_route_visit_report_signature',
        ...List.filled(7, 'save_route_visit_report_draft'), 'read_route_visit_report']);
    }, _RealHttpOverrides()));
  test('same capture cannot identify separate arrival and move', () {
    expect(() => const RouteVisitReportContext(sourceClockInId: 'source',
      routeAssignmentId: 'route', routeStopId: 'stop', startCaptureId: 'same',
      endCaptureId: 'same').toRpcParams(), throwsStateError);
  });
}
