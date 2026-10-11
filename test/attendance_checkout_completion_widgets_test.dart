import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_verification_page.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';
import 'package:sk_works/features/attendance/capture_verification_draft.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';

class _Repository implements AttendanceVerificationRepository {
  var inserts = 0;
  var actor = 'actor';
  bool open = true;
  final saved = <String, dynamic>{
    'id': 'end',
    'source_clock_in_id': 'start',
    'work_date': '2026-10-11',
    'site_id': null,
    'route_assignment_id': 'route',
    'confirmed_at': '2026-10-11T02:00:00Z',
  };
  AttendanceShiftContext get shift => AttendanceShiftContext(
    id: 'start',
    workerId: 'worker',
    workDate: DateTime(2026, 10, 11),
    clockIn: DateTime(2026, 10, 11, 9),
    verificationMode: 'manual',
    routeId: 'route',
  );
  @override
  String? get userId => actor;
  @override
  Future<List<Map<String, dynamic>>> loadWorkers() async => [
    {'id': 'worker', 'name': 'Worker'},
  ];
  @override
  Future<List<Map<String, dynamic>>> loadSites() async => [];
  @override
  Future<List<Map<String, dynamic>>> loadRecent({int limit = 20}) async => [];
  @override
  Future<Map<String, dynamic>> loadAttendanceSelectionWorkspace() async => {
    'selection': {'mode': 'manual', 'route_assignment_id': 'route'},
  };
  @override
  Future<HomeAttendanceStatus> loadHomeAttendanceStatus() async =>
      HomeAttendanceStatus(
        phase: open
            ? HomeAttendancePhase.working
            : HomeAttendancePhase.finished,
        selectedRouteId: 'route',
        selectedRouteName: 'Route',
        openShifts: open ? [shift] : [],
      );
  @override
  Future<bool> canManageAttendance() async => false;
  @override
  Future<CaptureVerificationDraft?> loadPendingCaptureDraft() async => null;
  @override
  Future<Map<String, dynamic>> createVerification({
    required String workerId,
    String? siteId,
    required String eventType,
    required String verificationMode,
    double? latitude,
    double? longitude,
    double? accuracyM,
    double? distanceToSiteM,
    required String proximityStatus,
    Uint8List? photoBytes,
    String? photoFilename,
    String? note,
    AttendanceShiftContext? shift,
    GpsPhotoCaptureResult? capture,
    void Function(CaptureVerificationDraft)? onCaptureDraftPrepared,
  }) async {
    expect(eventType, 'clock_out');
    expect(shift?.id, 'start');
    inserts++;
    open = false;
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'manual saved checkout survives failed report opening and then returns home without reinsertion',
    (tester) async {
      final repository = _Repository();
      var reports = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttendanceVerificationPage(
                      initialEventType: 'clock_out',
                      repository: repository,
                      openSavedReport: (context, saved) async {
                        expect(saved, repository.saved);
                        reports++;
                        if (reports == 1) {
                          throw StateError('report temporarily unavailable');
                        }
                      },
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('退勤を確定'));
      await tester.tap(find.text('退勤を確定'));
      await tester.pumpAndSettle();
      expect(repository.inserts, 1);
      expect(reports, 1);
      expect(find.textContaining('勤怠は登録済みです'), findsOneWidget);
      await tester.ensureVisible(find.text('登録済みの日報を開く'));
      await tester.tap(find.text('登録済みの日報を開く'));
      await tester.pumpAndSettle();
      expect(repository.inserts, 1);
      expect(reports, 2);
      expect(find.text('Open'), findsOneWidget);
    },
  );
  testWidgets('zero open shifts cannot create another checkout', (
    tester,
  ) async {
    final repository = _Repository()..open = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceVerificationPage(
          initialEventType: 'clock_out',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('退勤を確定'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(repository.inserts, 0);
  });
  testWidgets('archived clock-in keeps pending on back, then allows an explicit fresh start without inserting', (tester) async {
    final repository=ArchivedRepository()..open=false;
    await tester.pumpWidget(MaterialApp(home:AttendanceVerificationPage(initialEventType:'clock_in',repository:repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同じ撮影記録で再確認'));await tester.pumpAndSettle();
    expect(find.text('以前の出勤は履歴化されています'),findsOneWidget);
    await tester.tap(find.text('戻る'));await tester.pumpAndSettle();
    expect(repository.acknowledged,isFalse);expect(repository.inserts,0);
    await tester.tap(find.text('同じ撮影記録で再確認'));await tester.pumpAndSettle();
    await tester.tap(find.text('新しい出勤を始める'));await tester.pumpAndSettle();
    expect(repository.acknowledged,isTrue);expect(repository.inserts,0);
    expect(find.text('同じ撮影記録で再確認'),findsNothing);
    expect(find.text('出勤を確定'),findsOneWidget);
  });

}

class ArchivedRepository extends _Repository {
  final draft = CaptureVerificationDraft({'event_type':'clock_in','company_id':'company','worker_id':'worker','created_by':'actor','route_assignment_id':'route','site_id':null,'verification_mode':'location_photo','capture_contract_version':1,'photo_storage_path':'old.jpg'});
  bool acknowledged=false;
  @override
  Future<CaptureVerificationDraft?> loadPendingCaptureDraft() async => acknowledged ? null : draft;
  @override
  Future<Map<String,dynamic>> submitCaptureDraft(CaptureVerificationDraft d) async => throw const ArchivedCaptureVerification({});
  @override
  Future<void> acknowledgeArchivedCaptureDraft(CaptureVerificationDraft d) async {expect(d.id,draft.id);acknowledged=true;}
}
