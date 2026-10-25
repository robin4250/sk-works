import '../daily_reports/daily_report_company_allowance_selection.dart';
import '../shared/company_allowance_label_repository.dart';

/// Current catalog and worker eligibility only; no wage rates or payment proof.
class AttendanceManagementAllowanceOptions {
  const AttendanceManagementAllowanceOptions(this.labels, this.workers);
  final CompanyAllowanceLabelSnapshot labels;
  final Map<String, Set<String>> workers;

  Set<String> get sharedEligibleKeys {
    Set<String>? common;
    for (final keys in workers.values) {
      common = common == null ? Set<String>.from(keys) : common.intersection(keys);
    }
    return Set.unmodifiable(common ?? <String>{});
  }

  factory AttendanceManagementAllowanceOptions.parse(Object? raw, {
    required String companyId, required Iterable<String> workerIds,
  }) {
    Never invalid() => throw const FormatException('勤怠管理の共通手当を確認できません。');
    bool keys(Map value, Set<String> names) => value.length == names.length && value.keys.every(names.contains);
    final expected = workerIds.toSet();
    if (expected.isEmpty || raw is! Map ||
        !keys(raw, {'contract_version', 'company_id', 'labels', 'workers'}) ||
        raw['contract_version'] != 1 || raw['company_id'] != companyId || raw['workers'] is! List) {
      invalid();
    }
    final labels = CompanyAllowanceLabelSnapshot.parse(raw['labels'], companyId);
    final registered = {for (final item in labels.items) if (item.id != null) '${item.origin}/${item.id}': item};
    final result = <String, Set<String>>{};
    for (final worker in raw['workers'] as List) {
      if (worker is! Map || !keys(worker, {'worker_id', 'items'}) ||
          worker['worker_id'] is! String || !expected.contains(worker['worker_id']) ||
          result.containsKey(worker['worker_id']) || worker['items'] is! List) {
        invalid();
      }
      final allowed = <String>{};
      for (final identity in worker['items'] as List) {
        if (identity is! Map || !keys(identity, {'origin', 'id', 'generation', 'registration_version'})) invalid();
        final key = '${identity['origin']}/${identity['id']}';
        final item = registered[key];
        if (item == null || !item.selectable || !const ['day', 'hour'].contains(item.unit) ||
            identity['generation'] != item.generation ||
            identity['registration_version'] != item.registrationVersion || !allowed.add(key)) {
          invalid();
        }
      }
      result[worker['worker_id'] as String] = Set.unmodifiable(allowed);
    }
    if (result.length != expected.length) invalid();
    return AttendanceManagementAllowanceOptions(labels, Map.unmodifiable(result));
  }
}

/// Persisted identity metadata remains separate from freely entered names.
class AttendanceManagementSavedAllowances {
  const AttendanceManagementSavedAllowances({this.reportId, this.selections, this.legacyLabels});
  final String? reportId;
  final DailyReportCompanyAllowanceSelections? selections;
  final String? legacyLabels;
}
