import '../shared/company_allowance_label_repository.dart';

/// Selection metadata only. Prices and quantities belong to server capture.
class DailyReportCompanyAllowanceSelection {
  const DailyReportCompanyAllowanceSelection._({required this.origin,
    required this.id, required this.generation, required this.registrationVersion,
    required this.nameSnapshot, required this.unit});
  final String origin, id, nameSnapshot, unit;
  final int? generation;
  final int registrationVersion;
  String get key => '$origin/$id';

  factory DailyReportCompanyAllowanceSelection.registered(CompanyAllowanceLabel item) {
    if (!item.selectable || !const ['day', 'hour'].contains(item.unit)) {
      throw const FormatException('退勤で選択できる会社手当ではありません');
    }
    return DailyReportCompanyAllowanceSelection.fromJson({
      'origin': item.origin, 'id': item.id, 'generation': item.generation,
      'registration_version': item.registrationVersion,
      'name_snapshot': item.name, 'unit': item.unit,
    });
  }

  factory DailyReportCompanyAllowanceSelection.fromJson(Object? raw) {
    bool integer(Object? value, {bool zero = false}) => value is int &&
      value >= (zero ? 0 : 1) && value <= 9007199254740990;
    const keys = {'origin', 'id', 'generation', 'registration_version', 'name_snapshot', 'unit'};
    if (raw is! Map || raw.length != keys.length ||
        !raw.keys.every(keys.contains) ||
        !const ['company_legacy', 'company_common'].contains(raw['origin']) ||
        raw['id'] is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(raw['id'] as String) ||
        !integer(raw['registration_version'], zero: raw['origin'] == 'company_common') ||
        raw['name_snapshot'] is! String ||
        (raw['name_snapshot'] as String).trim().isEmpty ||
        (raw['name_snapshot'] as String).length > 4096 ||
        (raw['name_snapshot'] as String).trim() != raw['name_snapshot'] ||
        (raw['name_snapshot'] as String).contains(RegExp(r'[\r\n]')) ||
        !const ['day', 'hour'].contains(raw['unit']) ||
        (raw['origin'] == 'company_legacy'
          ? !integer(raw['generation']) : raw['generation'] != null)) {
      throw const FormatException('退勤の会社手当選択を確認できません');
    }
    return DailyReportCompanyAllowanceSelection._(
      origin: raw['origin'] as String, id: (raw['id'] as String).toLowerCase(),
      generation: raw['generation'] as int?,
      registrationVersion: raw['registration_version'] as int,
      nameSnapshot: raw['name_snapshot'] as String, unit: raw['unit'] as String);
  }

  Map<String, Object?> toJson() => {
    'origin': origin, 'id': id, 'generation': generation,
    'registration_version': registrationVersion,
    'name_snapshot': nameSnapshot, 'unit': unit,
  };
}

class DailyReportCompanyAllowanceSelections {
  DailyReportCompanyAllowanceSelections(Iterable<DailyReportCompanyAllowanceSelection> selected)
      : items = List.unmodifiable(selected.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    if (items.length > 303 || items.map((item) => item.key).toSet().length != items.length) {
      throw const FormatException('退勤の会社手当選択が重複しています');
    }
  }
  final List<DailyReportCompanyAllowanceSelection> items;
  factory DailyReportCompanyAllowanceSelections.fromJson(Object? raw) {
    if (raw is! Map || raw.length != 2 || raw['contract_version'] != 1 ||
        raw['items'] is! List) {
      throw const FormatException('退勤の会社手当保存状態を確認できません');
    }
    return DailyReportCompanyAllowanceSelections(
      (raw['items'] as List).map(DailyReportCompanyAllowanceSelection.fromJson));
  }
  Map<String, Object?> toJson() => {
    'contract_version': 1, 'items': items.map((item) => item.toJson()).toList(),
  };
}

/// Report-bound eligibility contains no rates or employee payroll settings.
Map<String, Set<String>> dailyReportCompanyAllowanceEligibility(Object? raw, {
  required String reportId, required Iterable<String> workerIds,
  required CompanyAllowanceLabelSnapshot snapshot,
}) {
  Never invalid() => throw const FormatException('退勤手当の適用対象を確認できません');
  bool keys(Map value, Set<String> expected) => value.length == expected.length && value.keys.every(expected.contains);
  if (raw is! Map || !keys(raw, {'contract_version', 'report_id', 'company_id', 'source_versions', 'workers'}) ||
      raw['contract_version'] != 1 || raw['report_id'] != reportId || raw['company_id'] != snapshot.companyId) { invalid(); }
  final versions = raw['source_versions'];
  if (versions is! Map || !keys(versions, {'legacy_version', 'common_version'}) ||
      versions['legacy_version'] != snapshot.legacyVersion || versions['common_version'] != snapshot.version) { invalid(); }
  final workers = raw['workers'];
  if (workers is! List) { invalid(); }
  final expected = workerIds.toSet();
  final registered = {for (final item in snapshot.items) if (item.id != null) '${item.origin}/${item.id}': item};
  final result = <String, Set<String>>{};
  for (final worker in workers) {
    if (worker is! Map || !keys(worker, {'worker_id', 'items'}) ||
        worker['worker_id'] is! String || !expected.contains(worker['worker_id']) ||
        result.containsKey(worker['worker_id']) || worker['items'] is! List) { invalid(); }
    final allowed = <String>{};
    for (final identity in worker['items'] as List) {
      if (identity is! Map || !keys(identity, {'origin', 'id', 'generation', 'registration_version'})) { invalid(); }
      final key = '${identity['origin']}/${identity['id']}';
      final item = registered[key];
      if (item == null || !item.selectable || !const ['day', 'hour'].contains(item.unit) ||
          identity['generation'] != item.generation || identity['registration_version'] != item.registrationVersion ||
          !allowed.add(key)) { invalid(); }
    }
    result[worker['worker_id'] as String] = Set.unmodifiable(allowed);
  }
  if (result.length != expected.length) { invalid(); }
  return Map.unmodifiable(result);
}
