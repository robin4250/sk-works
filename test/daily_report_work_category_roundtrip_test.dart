import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/group_checkout_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_repository.dart';
import 'package:sk_works/features/daily_reports/daily_report_company_allowance_selection.dart';
import 'package:sk_works/features/daily_reports/group_daily_report_roster.dart';
import 'package:sk_works/features/daily_reports/shared_worker_facts_repository.dart';

void main() {
  test('selected category reaches the draft RPC and survives source attachment', () {
    final saved = DailyReportWorkerDraft(workerId: 'worker', workerName: '作業者',
      workCategory: 'holiday_night', overtimeHours: 2);
    final merged = mergeAnchoredGroupRoster(existing: [saved], fallback: [],
      candidates: [GroupCheckoutCandidate(sourceId: 'source', workerId: 'worker',
        name: '作業者', workDate: DateTime(2026, 10, 26))], allowNewMembers: false).single;
    expect(merged.workCategory, 'holiday_night');
    expect(merged.toRpcJson()['work_category'], 'holiday_night');
    expect(merged.overtimeHours, 2);
    expect(merged.sourceClockInId, 'source');
  });
  test('missing category is not invented as a day shift', () {
    final draft = DailyReportWorkerDraft(workerId: 'worker', workerName: '作業者');
    expect(draft.workCategory, isNull);
    expect(draft.toRpcJson().containsKey('work_category'), isFalse);
  });
  test('confirmed category survives conversion to editable report facts', () {
    final facts = SharedWorkerFacts(overtimeHours: 0, earlyHours: 0, nightHours: 0,
      workCategory: 'night', allowanceAmount: 0, allowanceLabel: null,
      companyAllowanceSelections: DailyReportCompanyAllowanceSelections([]),
      legacyLabels: null, vehicleId: null, routeId: null, odometerKm: null);
    final draft = facts.toDraft(workerId: 'worker', workerName: '作業者');
    expect(draft.workCategory, 'night');
    expect(draft.toRpcJson()['work_category'], 'night');
  });
}
