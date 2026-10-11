import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';
import 'package:sk_works/features/attendance/route_journey_capture_page.dart';

class _TwoSourceAccess
    implements RouteJourneyCaptureAccess, RouteVisitReportAccess {
  @override
  String get userId => 'actor';
  final sources = <String>[];
  final chosenSources = <String>[];
  final finishedSources = <String>[];
  int writes = 0;
  final otherCapture = RouteJourneyCaptureDraft(
    userId: 'actor',
    companyId: 'company',
    sourceId: 'new-source',
    stopId: 'new-stop',
    originKind: 'company',
    visitKind: 'start',
    payload: {'capture_contract_version': 1},
  );
  late RouteVisitReportPending? report = _oldReport();
  RouteVisitReportPending _oldReport() {
    final move = RouteJourneyCaptureDraft(
      userId: 'actor',
      companyId: 'company',
      sourceId: 'old-source',
      stopId: 'old-stop',
      originKind: 'company',
      visitKind: 'end',
      startCaptureId: 'old-arrival',
      payload: {'capture_contract_version': 1},
    );
    return RouteVisitReportPending.fromSaved(move, {
      'id': move.id,
      'created_by': 'actor',
      'company_id': 'company',
      'source_clock_in_id': 'old-source',
      'route_stop_id': 'old-stop',
      'origin_kind': 'company',
      'visit_kind': 'end',
      'start_capture_id': 'old-arrival',
      'work_date': '2026-10-10',
      'recorded_at': '2026-10-10T10:00:00Z',
      'payload': move.payload,
    });
  }

  @override
  Future<List<RouteJourneyCaptureDraft>> allPending() async => [otherCapture];
  @override
  Future<RouteJourneyCaptureDraft?> loadPending(String companyId) async =>
      otherCapture;
  @override
  Future<List<RouteVisitReportPending>> allPendingReports() async => [
    if (report != null) report!,
  ];
  @override
  Future<Map<String, dynamic>> workspace(String sourceId) async {
    sources.add(sourceId);
    return {
      'version': 1,
      'visit_contract_version': 1,
      'visits': [],
      'stops': [],
      'source_clock_in_id': sourceId,
      'company_id': 'company',
      'worker_id': 'worker',
      'route_assignment_id': sourceId == 'old-source'
          ? 'old-route'
          : 'new-route',
      'work_date': sourceId == 'old-source' ? '2026-10-10' : '2026-10-11',
      'enabled': false,
      'is_open': false,
      'origin_kind': 'company',
    };
  }

  @override
  Future<RouteVisitReportPending> chooseReport(
    RouteVisitReportPending pending,
    String choice,
  ) async {
    chosenSources.add(pending.sourceId);
    return pending.withChoice('skip');
  }

  @override
  Future<void> finishReport(RouteVisitReportPending pending) async {
    finishedSources.add(pending.sourceId);
    report = null;
  }

  @override
  Future<Map<String, dynamic>> submit(RouteJourneyCaptureDraft draft) async {
    writes++;
    throw StateError('Must not submit another shift');
  }

  @override
  Future<String> upload(
    CapturedPhoto photo,
    CaptureShiftContext context,
    String workerId,
  ) async {
    writes++;
    throw StateError('Must not capture on resume');
  }
}

void main() {
  testWidgets('closed report A stays on A when company movement B is pending', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final access = _TwoSourceAccess();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteJourneyCapturePage(sourceId: 'old-source', access: access),
      ),
    );
    await tester.pumpAndSettle();
    expect(access.sources, ['old-source']);
    expect(find.text('勤務日: 2026-10-10'), findsOneWidget);
    expect(find.text('現場日報を再開'), findsOneWidget);
    expect(find.text('同じ途中現場記録で再確認'), findsNothing);
    await tester.tap(find.text('現場日報を再開'));
    await tester.pumpAndSettle();
    expect(find.text('この現場の日報を作成しますか？'), findsOneWidget);
    await tester.tap(find.text('作成しない'));
    await tester.pumpAndSettle();
    expect(access.chosenSources, ['old-source']);
    expect(access.finishedSources, ['old-source']);
    expect(access.sources, ['old-source', 'old-source']);
    expect(find.text('現場日報を再開'), findsNothing);
    expect(access.writes, 0);
    expect(access.otherCapture.sourceId, 'new-source');
  });
}
