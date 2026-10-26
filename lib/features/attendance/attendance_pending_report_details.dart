import '../daily_reports/daily_report_company_allowance_selection.dart';

/// Saved draft inputs are reference information, never finalized attendance or pay.
class AttendancePendingReportDetails {
  const AttendancePendingReportDetails({required this.reportId, required this.date,
    required this.siteName, required this.overtimeHours, required this.earlyHours,
    required this.nightHours, required this.allowanceNames, required this.selections});
  final String reportId, siteName;
  final DateTime date;
  final double overtimeHours, earlyHours, nightHours;
  final List<String> allowanceNames;
  final List<DailyReportCompanyAllowanceSelection> selections;

  static List<AttendancePendingReportDetails> parse(Iterable<dynamic> rows,
      {required String workerId, required DateTime month}) {
    final result = <AttendancePendingReportDetails>[];
    final seen = <String>{};
    for (final raw in rows) {
      if (raw is! Map || raw['worker_id'] != workerId || raw['report_id'] is! String) {
        throw const FormatException('未確定日報の対象を確認できません。');
      }
      final report = raw['daily_reports'];
      if (report is! Map || report['id'] != raw['report_id'] || report['status'] != 'draft') {
        throw const FormatException('未確定日報の保存状態を確認できません。');
      }
      final date = DateTime.tryParse(report['report_date']?.toString() ?? '');
      if (date == null || date.year != month.year || date.month != month.month ||
          !seen.add(raw['report_id'] as String)) {
        throw const FormatException('未確定日報の日付を確認できません。');
      }
      double hours(String key) {
        final value = raw[key];
        if (value is! num || !value.isFinite || value < 0 || value > 24) {
          throw const FormatException('未確定日報の時間を確認できません。');
        }
        return value.toDouble();
      }
      final selections = raw['company_allowance_selections'] == null
          ? const <DailyReportCompanyAllowanceSelection>[]
          : DailyReportCompanyAllowanceSelections.fromJson(raw['company_allowance_selections']).items;
      final names = <String>{for (final item in selections) item.nameSnapshot};
      final label = raw['allowance_label'];
      if (label != null && label is! String) {
        throw const FormatException('未確定日報の手当名を確認できません。');
      }
      if (label is String && label.trim().isNotEmpty) { names.add(label.trim()); }
      final site = report['sites'];
      result.add(AttendancePendingReportDetails(reportId: raw['report_id'] as String,
        date: DateTime(date.year, date.month, date.day),
        siteName: site is Map ? site['name']?.toString() ?? '' : '',
        overtimeHours: hours('overtime_hours'), earlyHours: hours('early_hours'),
        nightHours: hours('night_hours'), allowanceNames: List.unmodifiable(names),
        selections: List.unmodifiable(selections)));
    }
    return List.unmodifiable(result);
  }
}
