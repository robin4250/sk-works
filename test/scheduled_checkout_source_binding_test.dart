import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/attendance_shift_context.dart';
import 'package:sk_works/features/attendance/attendance_verification_page.dart';
import 'package:sk_works/features/attendance/attendance_verification_repository.dart';
import 'package:sk_works/features/attendance/capture_verification_draft.dart';
import 'package:sk_works/features/attendance/checkout_report_gate.dart';
import 'package:sk_works/features/attendance/checkout_report_gate_repository.dart';
import 'package:sk_works/features/attendance/gps_photo_capture_result.dart';
import 'package:sk_works/features/attendance/scheduled_checkout_repository.dart';
import 'package:sk_works/features/notifications/notification_bell.dart';

class _Repository implements AttendanceVerificationRepository {
  List<String> sources = ['older', 'selected'];
  CaptureVerificationDraft? pending;
  String? returnedSource;
  int writes = 0;
  String? savedSource;
  DateTime? savedWorkDate;
  @override String? get userId => 'actor';
  @override Future<List<Map<String, dynamic>>> loadWorkers() async => [
    {'id': 'worker', 'name': '勤務者'},
  ];
  @override Future<List<Map<String, dynamic>>> loadSites() async => [];
  @override Future<List<Map<String, dynamic>>> loadRecent({int limit = 20}) async => [];
  @override Future<Map<String, dynamic>> loadAttendanceSelectionWorkspace() async => {
    'selection': {'mode': 'manual', 'route_assignment_id': 'route'},
  };
  @override Future<HomeAttendanceStatus> loadHomeAttendanceStatus() async => HomeAttendanceStatus(
    phase: HomeAttendancePhase.working, selectedRouteId: 'route',
    openShifts: [for (final id in sources) AttendanceShiftContext(id: id,
      workerId: 'worker', workDate: DateTime(2026, 10, 11),
      clockIn: DateTime(2026, 10, 11, 9), verificationMode: 'manual', routeId: 'route')]);
  @override Future<bool> canManageAttendance() async => false;
  @override Future<String> captureCompanyId() async => 'company';
  @override Future<CaptureVerificationDraft?> loadPendingCaptureDraft() async => pending;
  @override Future<Map<String, dynamic>> createVerification({
    required String workerId, String? siteId, required String eventType,
    required String verificationMode, double? latitude, double? longitude,
    double? accuracyM, double? distanceToSiteM, required String proximityStatus,
    Uint8List? photoBytes, String? photoFilename, String? note,
    AttendanceShiftContext? shift, GpsPhotoCaptureResult? capture,
    void Function(CaptureVerificationDraft)? onCaptureDraftPrepared,
  }) async {
    writes++;
    savedSource = shift?.id;
    savedWorkDate = shift?.workDate;
    return {'id': 'out', 'source_clock_in_id': returnedSource ?? shift?.id,
      'work_date': shift?.workDate.toIso8601String().substring(0, 10), 'site_id': shift?.siteId,
      'route_assignment_id': shift?.routeId};
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _NightRepository extends _Repository {
  @override Future<HomeAttendanceStatus> loadHomeAttendanceStatus() async => HomeAttendanceStatus(
    phase: HomeAttendancePhase.working, selectedRouteId: 'route',
    openShifts: [AttendanceShiftContext(id: 'selected', workerId: 'worker',
      workDate: DateTime(2026, 10, 11), clockIn: DateTime(2026, 10, 11, 22),
      verificationMode: 'manual', routeId: 'route')]);
}

class _SiteRepository extends _Repository {
  @override Future<List<Map<String, dynamic>>> loadSites() async => [
    {'id': 'site', 'name': '対象現場'},
  ];
  @override Future<Map<String, dynamic>> loadAttendanceSelectionWorkspace() async => {
    'selection': {'mode': 'manual', 'site_id': 'site'},
  };
  @override Future<HomeAttendanceStatus> loadHomeAttendanceStatus() async => HomeAttendanceStatus(
    phase: HomeAttendancePhase.working, openShifts: [AttendanceShiftContext(id: 'selected',
      workerId: 'worker', workDate: DateTime(2026, 10, 11),
      clockIn: DateTime(2026, 10, 11, 9), verificationMode: 'manual', siteId: 'site')]);
}
class _OffGateRepository implements CheckoutReportGateRepository {
  @override String? get actorId => 'actor';
  @override bool? get enforcementEnabled => false;
  @override String? get effectiveFrom => null;
  @override Future<List<PendingCheckoutRegistration>> readPending() async => [];
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(WidgetTester tester, _Repository repository,
      Future<void> Function(BuildContext, Map<String, dynamic>) onSaved,
      {ScheduledCheckoutTarget? target}) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AttendanceVerificationPage(
          initialEventType: 'clock_out', initialSourceClockInId: 'selected',
          scheduledCheckoutTarget: target,
          repository: repository, openSavedReport: onSaved))), child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.text('退勤を確定'));
    await tester.tap(find.text('退勤を確定'));
    await tester.pumpAndSettle();
  }
  testWidgets('scheduled confirmation binds the selected source rather than the first open shift', (tester) async {
    final repository = _Repository();
    var opened = 0;
    await open(tester, repository, (_, saved) async {
      expect(saved['source_clock_in_id'], 'selected');
      opened++;
    });
    final picker = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('shift:selected:2')));
    expect(picker.onChanged, isNull);
    expect(find.byType(SkoNotificationBell), findsNothing);
    await confirm(tester);
    expect(repository.savedSource, 'selected');
    expect(repository.writes, 1);
    expect(opened, 1);
  });
  testWidgets('overnight checkout retains the exact original clock-in work date', (tester) async {
    final repository = _NightRepository();
    final target = ScheduledCheckoutTarget(companyId: 'company', workerId: 'worker',
      sourceId: 'selected', workDate: '2026-10-11', routeId: 'route',
      reminderAt: DateTime.utc(2026, 10, 12, 6), due: true,
      scopeFingerprint: 'night-source', canManageAttendance: false);
    await open(tester, repository, (_, saved) async {
      expect(saved['work_date'], '2026-10-11');
    }, target: target);
    await confirm(tester);
    expect(repository.savedWorkDate, DateTime(2026, 10, 11));
    expect(repository.writes, 1);
  });
  testWidgets('a matching source id with changed worker or work date is not another checkout target', (tester) async {
    final repository = _Repository();
    final target = ScheduledCheckoutTarget(companyId: 'company', workerId: 'different-worker',
      sourceId: 'selected', workDate: '2026-10-12', routeId: 'route',
      reminderAt: DateTime.utc(2026, 10, 12, 6), due: true,
      scopeFingerprint: 'changed-scope', canManageAttendance: false);
    await open(tester, repository, (_, __) async => fail('must not open a report'), target: target);
    expect(find.textContaining('通知の本人・会社・勤務日・現場が一致しません'), findsOneWidget);
    expect(repository.writes, 0);
  });
  testWidgets('missing scheduled source cannot silently select another saved shift', (tester) async {
    final repository = _Repository()..sources = ['older'];
    await open(tester, repository, (_, __) async => fail('must not open a report'));
    expect(find.textContaining('通知の勤務原本を確認できません'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('退勤を確定'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton)));
    expect(button.onPressed, isNull);
    expect(repository.writes, 0);
  });
  testWidgets('a pending capture for another source is retained instead of being reassigned', (tester) async {
    final repository = _Repository()..pending = CaptureVerificationDraft({
      'event_type': 'clock_out', 'source_clock_in_id': 'older',
      'company_id': 'company', 'worker_id': 'worker', 'created_by': 'actor',
      'site_id': null, 'route_assignment_id': 'route',
      'verification_mode': 'location_photo', 'capture_contract_version': 1,
      'photo_storage_path': 'existing.jpg',
    });
    final retained = repository.pending;
    await open(tester, repository, (_, __) async => fail('must not open a report'));
    expect(find.textContaining('通知の勤務原本を確認できません'), findsOneWidget);
    expect(repository.pending, same(retained));
    expect(repository.writes, 0);
  });
  testWidgets('a mismatching saved checkout never opens or certifies the scheduled report', (tester) async {
    final repository = _Repository()..returnedSource = 'older';
    await open(tester, repository, (_, __) async => fail('must not open a report'));
    await confirm(tester);
    expect(repository.writes, 1);
    expect(find.textContaining('通知と保存された退勤の勤務原本が一致しません'), findsOneWidget);
  });
  testWidgets('an active but explicitly OFF report gate preserves group checkout then legacy report flow', (tester) async {
    final repository = _SiteRepository();
    final controller = CheckoutReportGateController.instance;
    final activation = controller.activate('actor', () async {});
    final order = <String>[];
    await tester.pumpWidget(CheckoutReportBackBoundary(controller: controller,
      child: MaterialApp(builder: (_, child) => CheckoutReportGate(
        controller: controller, repository: _OffGateRepository(), child: child!),
        home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttendanceVerificationPage(
            initialEventType: 'clock_out', initialSourceClockInId: 'selected', repository: repository,
            groupCheckoutForTesting: (context, source, day) async {
              expect(source, 'selected');
              order.add('group');
              await showDialog<void>(context: context, builder: (context) => AlertDialog(
                title: const Text('group-checkout-dialog'), actions: [TextButton(
                  onPressed: () => Navigator.pop(context), child: const Text('continue-to-report'))]));
            },
            openSavedReport: (_, saved) async { order.add('report'); },
          ))), child: const Text('Open')))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(find.text('group-checkout-dialog'), findsOneWidget);
    expect(order, ['group']);
    await tester.tap(find.text('continue-to-report'));
    await tester.pumpAndSettle();
    expect(order, ['group', 'report']);
    expect(repository.writes, 1);
    expect(find.text('Open'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.deactivate('actor', activation);
  });
}
