import '../daily_reports/daily_report_company_allowance_selection.dart';

/// Uses saved identity/name snapshots only; never current catalog names or rates.
Map<String, List<DailyReportCompanyAllowanceSelection>>
    workerAttendanceRegisteredAllowances(Iterable<dynamic> rows,
        {required Set<String> reportIds, required String workerId}) {
  final result = <String, List<DailyReportCompanyAllowanceSelection>>{};
  for (final raw in rows) {
    if (raw is! Map || raw['report_id'] is! String ||
        !reportIds.contains(raw['report_id']) || raw['worker_id'] != workerId ||
        result.containsKey(raw['report_id'])) {
      throw const FormatException('出勤表の共通手当の保存状態を確認できません');
    }
    final report = raw['daily_reports'];
    if (report is! Map || report['status'] is! String) {
      throw const FormatException('出勤表の日報確定状態を確認できません');
    }
    // Two signatures on a draft are document-only, not formal finalization.
    if (report['status'] != 'signed') continue;
    final saved = raw['company_allowance_selections'];
    result[raw['report_id'] as String] = saved == null
        ? const <DailyReportCompanyAllowanceSelection>[]
        : DailyReportCompanyAllowanceSelections.fromJson(saved).items;
  }
  return Map.unmodifiable(result);
}
