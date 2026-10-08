import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/group_checkout_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/group_daily_report_roster.dart';

void main() {
  test('attachment result must identify exact report and source IDs', () {
    expect(groupReportSourcesAttached({'daily_report_id': 'report', 'source_clock_in_ids': ['b', 'a']}, 'report', ['a', 'b']), isTrue);
    expect(groupReportSourcesAttached({'daily_report_id': 'other', 'source_clock_in_ids': ['a', 'b']}, 'report', ['a', 'b']), isFalse);
    expect(groupReportSourcesAttached({'daily_report_id': 'report', 'source_clock_in_ids': ['a', 'a']}, 'report', ['a', 'b']), isFalse);
  });
  final date = DateTime(2026, 10, 31);
  final candidates = [
    GroupCheckoutCandidate(sourceId: 'in-one', workerId: 'one', name: '一人目', workDate: date),
    GroupCheckoutCandidate(sourceId: 'in-two', workerId: 'two', name: '二人目', workDate: date,
      clockOutAt: DateTime(2026, 10, 31, 23)),
  ];
  test('actual clock-in IDs follow roster without losing saved pay inputs or early-leave member', () {
    final saved = DailyReportWorkerDraft(workerId: 'one', workerName: '一人目',
      overtimeHours: 2, earlyHours: 1, allowanceAmount: 500, allowanceLabel: '手当',
      vehicleId: 'vehicle', odometerKm: 12345, meterManaged: true, meterEventId: 'meter',
      previousOdometerKm: 12300, tripDistanceKm: 45, meterSourceClockInId: 'in-one');
    final rows = mergeAnchoredGroupRoster(existing: [saved], fallback: [], candidates: candidates,
      allowNewMembers: true);
    expect(rows.map((row) => row.sourceClockInId), ['in-one', 'in-two']);
    expect(rows.first.overtimeHours, 2);
    expect(rows.first.earlyHours, 1);
    expect(rows.first.allowanceAmount, 500);
    expect(rows.first.odometerKm, 12345);
    expect(rows.first.meterEventId, 'meter');
    expect(rows.first.previousOdometerKm, 12300);
    expect(rows.first.tripDistanceKm, 45);
    expect(saved.sourceClockInId, isNull);
    expect(rows.last.workerId, 'two');
    expect(rows.last.sourceClockOutAt, DateTime(2026, 10, 31, 23));
    expect(rows.first.sourceClockOutAt, isNull);
  });
  test('signed report never adds a participant before approved edit', () {
    final rows = mergeAnchoredGroupRoster(existing: [DailyReportWorkerDraft(workerId: 'one', workerName: '一人目')],
      fallback: [], candidates: candidates, allowNewMembers: false);
    expect(rows.length, 1);
    expect(rows.single.sourceClockInId, 'in-one');
  });
  test('previously saved manual member is retained and never assigned invented GPS source', () {
    final rows = mergeAnchoredGroupRoster(existing: [DailyReportWorkerDraft(workerId: 'manual', workerName: '手動')],
      fallback: [], candidates: candidates, allowNewMembers: true);
    expect(rows.first.workerId, 'manual');
    expect(rows.first.sourceClockInId, isNull);
    expect(rows.length, 3);
  });
}
