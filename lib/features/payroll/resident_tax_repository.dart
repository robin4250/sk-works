import '../../data/supabase_backend.dart';

String validateResidentTaxMonth(String text) {
  final value = text.trim();
  if (!RegExp(r'^(?!0000)\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(value)) {
    throw const FormatException('開始年月はYYYY-MMで入力してください');
  }
  return value;
}

Map<String, dynamic> _object(dynamic raw) {
  if (raw is! Map) {
    throw const FormatException('住民税設定を確認できません');
  }
  return Map<String, dynamic>.from(raw);
}

class ResidentTaxEntry {
  const ResidentTaxEntry({required this.month, required this.amount});
  final String month;
  final int amount;
  Map<String, dynamic> toJson() => {'effective_month': month, 'amount_yen': amount};
  factory ResidentTaxEntry.fromJson(dynamic raw) {
    final row = _object(raw);
    if (row['effective_month'] is! String || row['amount_yen'] is! int || (row['amount_yen'] as int) < 0 || (row['amount_yen'] as int) > 2147483647) {
      throw const FormatException('住民税の開始年月・月額を確認できません');
    }
    return ResidentTaxEntry(month: validateResidentTaxMonth(row['effective_month'] as String), amount: row['amount_yen'] as int);
  }
}

class ResidentTaxState {
  const ResidentTaxState({required this.version, required this.mode, required this.cutover,
    required this.entries, required this.updatedBy, required this.updatedAt});
  final int version;
  final String mode;
  final String? cutover;
  final List<ResidentTaxEntry> entries;
  final String updatedBy;
  final String updatedAt;
  factory ResidentTaxState.fromJson(dynamic raw) {
    final row = _object(raw);
    if (row['version'] is! int || (row['version'] as int) < 1 || !['legacy', 'timeline'].contains(row['mode']) ||
        row['entries'] is! List || row['updated_by'] is! String || row['updated_at'] is! String) {
      throw const FormatException('住民税設定の状態を確認できません');
    }
    final entries = (row['entries'] as List).map(ResidentTaxEntry.fromJson).toList();
    final mode = row['mode'] as String;
    final cutover = row['cutover_month'];
    if (mode == 'legacy' && (cutover != null || entries.isNotEmpty)) {
      throw const FormatException('従来設定の状態を確認できません');
    }
    if (mode == 'timeline' && (cutover is! String || entries.isEmpty || entries.length > 120 ||
        entries.first.month != cutover)) {
      throw const FormatException('住民税の開始年月を確認できません');
    }
    for (var index = 1; index < entries.length; index++) {
      if (entries[index - 1].month.compareTo(entries[index].month) >= 0) {
        throw const FormatException('住民税の開始年月が重複しています');
      }
    }
    return ResidentTaxState(version: row['version'] as int, mode: mode, cutover: cutover as String?,
      entries: List.unmodifiable(entries), updatedBy: row['updated_by'] as String, updatedAt: row['updated_at'] as String);
  }
}

class ResidentTaxData {
  const ResidentTaxData({required this.companyId, required this.state, required this.mode,
    required this.amount, required this.effectiveMonth, required this.history});
  final String companyId;
  final ResidentTaxState? state;
  final String mode;
  final int amount;
  final String? effectiveMonth;
  final List<Map<String, dynamic>> history;
  factory ResidentTaxData.fromJson(dynamic raw, String companyId, String month) {
    final row = _object(raw);
    if (!row.containsKey('state') || row['history'] is! List) {
      throw const FormatException('住民税設定を取得できません');
    }
    final state = row['state'] == null ? null : ResidentTaxState.fromJson(row['state']);
    final resolved = _object(row['resolved']);
    if (!['legacy', 'timeline'].contains(resolved['mode']) || resolved['amount_yen'] is! int ||
        (resolved['amount_yen'] as int) < 0 || (resolved['amount_yen'] as int) > 2147483647) {
      throw const FormatException('適用する住民税を確認できません');
    }
    final mode = resolved['mode'] as String;
    String? effective;
    if (mode == 'timeline') {
      if (state == null || state.mode != 'timeline' || resolved['effective_month'] is! String) {
        throw const FormatException('住民税の適用元を確認できません');
      }
      effective = validateResidentTaxMonth(resolved['effective_month'] as String);
      final eligible = state.entries.where((entry) => entry.month.compareTo(month) <= 0).toList();
      if (eligible.isEmpty || eligible.last.month != effective || eligible.last.amount != resolved['amount_yen']) {
        throw const FormatException('住民税の適用年月が一致しません');
      }
    } else if (state?.mode == 'timeline' && state!.cutover!.compareTo(month) <= 0) {
      throw const FormatException('開始後の住民税設定を確認できません');
    }
    return ResidentTaxData(companyId: companyId, state: state, mode: mode, amount: resolved['amount_yen'] as int,
      effectiveMonth: effective, history: List.unmodifiable((row['history'] as List).map(_object)));
  }
}

bool residentTaxStateMatches(ResidentTaxState? actual, ResidentTaxState expected) {
  if (actual == null || actual.version != expected.version || actual.mode != expected.mode ||
      actual.cutover != expected.cutover || actual.entries.length != expected.entries.length) {
    return false;
  }
  for (var index = 0; index < actual.entries.length; index++) {
    if (actual.entries[index].month != expected.entries[index].month || actual.entries[index].amount != expected.entries[index].amount) {
      return false;
    }
  }
  return true;
}

List<ResidentTaxEntry> residentTaxEntriesWithMonth(List<ResidentTaxEntry> existing, ResidentTaxEntry added) {
  final entries = [...existing.where((entry) => entry.month != added.month), added]..sort((left, right) => left.month.compareTo(right.month));
  if (entries.length > 120) {
    throw const FormatException('開始年月は120件まで登録できます');
  }
  return entries;
}

abstract class ResidentTaxRepository {
  Future<ResidentTaxData> read(String workerId, String month, {String? companyId});
  Future<ResidentTaxState> save({required String companyId, required String workerId, required int expectedVersion,
    required String mode, required String? cutover, required List<ResidentTaxEntry> entries});
}

typedef ResidentTaxRpc = Future<dynamic> Function(String name, Map<String, dynamic> parameters);
class SupabaseResidentTaxRepository implements ResidentTaxRepository {
  SupabaseResidentTaxRepository({ResidentTaxRpc? rpc, Future<String> Function(String workerId)? resolveCompany}) : _rpc = rpc, _resolveWorkerCompany = resolveCompany;
  final ResidentTaxRpc? _rpc;
  final Future<String> Function(String workerId)? _resolveWorkerCompany;
  Future<String> _resolveCompany(String workerId) async {
    if (_resolveWorkerCompany != null) {
      return _resolveWorkerCompany(workerId);
    }
    final rows = await SupabaseBackend.client.from('workers').select('company_id').eq('id', workerId).limit(1);
    if (rows.isEmpty || rows.first['company_id'] is! String) {
      throw StateError('対象社員の会社情報を確認できません');
    }
    return rows.first['company_id'] as String;
  }
  Future<dynamic> _call(String name, Map<String, dynamic> parameters) async {
    if (_rpc != null) {
      return _rpc(name, parameters);
    }
    return SupabaseBackend.client.rpc(name, params: parameters);
  }
  @override
  Future<ResidentTaxData> read(String workerId, String month, {String? companyId}) async {
    validateResidentTaxMonth(month);
    final resolvedCompanyId = companyId ?? await _resolveCompany(workerId);
    final raw = await _call('read_worker_resident_tax_schedule', {'p_company_id': resolvedCompanyId, 'p_worker_id': workerId, 'p_month': month});
    return ResidentTaxData.fromJson(raw, resolvedCompanyId, month);
  }
  @override
  Future<ResidentTaxState> save({required String companyId, required String workerId, required int expectedVersion,
    required String mode, required String? cutover, required List<ResidentTaxEntry> entries}) async {
    for (final entry in entries) { ResidentTaxEntry.fromJson(entry.toJson()); }
    final raw = await _call('save_worker_resident_tax_schedule', {'p_company_id': companyId, 'p_worker_id': workerId,
      'p_expected_version': expectedVersion, 'p_mode': mode, 'p_cutover_month': cutover,
      'p_entries': entries.map((entry) => entry.toJson()).toList(), 'p_confirmed': true});
    final saved = ResidentTaxState.fromJson(raw);
    if (saved.version != expectedVersion + 1 || saved.mode != mode || saved.cutover != cutover || saved.entries.length != entries.length) {
      throw const FormatException('住民税の保存結果を確認できません');
    }
    for (var index = 0; index < entries.length; index++) {
      if (saved.entries[index].month != entries[index].month || saved.entries[index].amount != entries[index].amount) {
        throw const FormatException('住民税の保存結果が一致しません');
      }
    }
    return saved;
  }
}
