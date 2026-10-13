import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';
import 'package:sk_works/features/attendance/route_journey_capture_draft.dart';
import 'package:sk_works/features/attendance/route_journey_capture_page.dart';

class JourneyFixture
    implements RouteJourneyCaptureAccess, RouteVisitReportAccess {
  JourneyFixture(this.stopCount);
  final int stopCount;
  final visits = <Map<String, dynamic>>[];
  RouteVisitReportPending? report;
  int writes = 0, finished = 0;
  @override
  String get userId => 'actor';
  @override
  Future<List<RouteJourneyCaptureDraft>> allPending() async => [];
  @override
  Future<RouteJourneyCaptureDraft?> loadPending(String companyId) async => null;
  @override
  Future<Map<String, dynamic>> workspace(String sourceId) async => {
    'company_id': 'company',
    'worker_id': 'worker',
    'source_clock_in_id': sourceId,
    'route_assignment_id': 'route',
    'work_date': '2026-10-11',
    'enabled': true,
    'is_open': true,
    'verification_mode': 'manual',
    'visit_contract_version': 1,
    'origin_kind': 'direct',
    'visits': visits,
    'stops': [
      for (var i = 0; i < stopCount; i++)
        {'id': 'stop-$i', 'stop_order': i + 1, 'label': '現場$i'},
    ],
  };
  @override
  Future<Map<String, dynamic>> submit(RouteJourneyCaptureDraft d) async {
    writes++;
    expect(d.originKind, 'direct');
    final saved = <String, dynamic>{
      'id': d.id,
      'created_by': d.userId,
      'company_id': d.companyId,
      'source_clock_in_id': d.sourceId,
      'route_stop_id': d.stopId,
      'origin_kind': d.originKind,
      'visit_kind': d.visitKind,
      'start_capture_id': d.visitStartId,
      'work_date': '2026-10-11',
      'recorded_at': d.payload['attempted_at'],
      'payload': d.payload,
    };
    if (d.visitKind == 'start') {
      visits.add({
        'start_capture_id': d.id,
        'route_stop_id': d.stopId,
        'work_date': '2026-10-11',
        'started_at': d.payload['attempted_at'],
        'end_capture_id': null,
        'ended_at': null,
      });
    } else {
      final v = visits.singleWhere(
        (v) => v['start_capture_id'] == d.startCaptureId,
      );
      v['end_capture_id'] = d.id;
      v['ended_at'] = d.payload['attempted_at'];
      report = RouteVisitReportPending.fromSaved(d, saved);
    }
    return saved;
  }

  @override
  Future<String> upload(
    CapturedPhoto p,
    CaptureShiftContext c,
    String worker,
  ) async => throw StateError('manual visit cannot upload');
  @override
  Future<List<RouteVisitReportPending>> allPendingReports() async => [
    if (report != null) report!,
  ];
  @override
  Future<RouteVisitReportPending> chooseReport(
    RouteVisitReportPending p,
    String choice,
  ) async => report = p.withChoice(choice);
  @override
  Future<void> finishReport(RouteVisitReportPending p) async {
    finished++;
    report = null;
  }
}

void main() {
  Future<void> open(WidgetTester tester, JourneyFixture fixture) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RouteJourneyCapturePage(
                    sourceId: 'source',
                    access: fixture,
                  ),
                ),
              ),
              child: const Text('TOP'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('TOP'));
    await tester.pumpAndSettle();
  }

  Future<void> arrive(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1. 現場0').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '現場到着'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'intermediate arrival confirms guidance before returning to TOP',
    (tester) async {
      final fixture = JourneyFixture(2);
      await open(tester, fixture);
      expect(find.text('会社出勤後に現場へ'), findsNothing);
      expect(find.text('直行直帰'), findsNothing);
      expect(find.text('作業する現場を選び、現場到着のボタンを押してください'), findsOneWidget);
      await arrive(tester);
      expect(find.text('作業終了して次の現場に向かう時に現場移動ボタン押してください'), findsOneWidget);
      expect(fixture.writes, 1);
      await tester.tap(find.text('確認'));
      await tester.pumpAndSettle();
      expect(find.text('TOP'), findsOneWidget);
    },
  );
  testWidgets(
    'single final arrival returns to TOP without requiring movement',
    (tester) async {
      final fixture = JourneyFixture(1);
      await open(tester, fixture);
      await arrive(tester);
      expect(find.text('TOP'), findsOneWidget);
      expect(fixture.writes, 1);
      expect(fixture.visits.single['end_capture_id'], isNull);
    },
  );
  testWidgets(
    'saved movement waits for report choice before next-arrival guidance',
    (tester) async {
      final fixture = JourneyFixture(2)
        ..visits.add({
          'start_capture_id': 'arrival',
          'route_stop_id': 'stop-0',
          'work_date': '2026-10-11',
          'started_at': '2026-10-11T08:00:00Z',
          'end_capture_id': null,
          'ended_at': null,
        });
      await open(tester, fixture);
      await tester.tap(find.widgetWithText(FilledButton, '現場移動'));
      await tester.pumpAndSettle();
      expect(find.text('この現場の日報を作成しますか？'), findsOneWidget);
      expect(find.text('次の現場に到着したら現場到着ボタンを押してください'), findsNothing);
      expect(fixture.finished, 0);
      expect(fixture.writes, 1);
      await tester.tap(find.text('作成しない'));
      await tester.pumpAndSettle();
      expect(fixture.finished, 1);
      expect(find.text('次の現場に到着したら現場到着ボタンを押してください'), findsOneWidget);
      await tester.tap(find.text('確認'));
      await tester.pumpAndSettle();
      expect(find.text('TOP'), findsOneWidget);
      expect(fixture.writes, 1);
    },
  );
}
