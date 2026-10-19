import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

int residentTaxAnnualYen(Object? value) {
  if (value is! int || value < 0 || value > 2147483647) {
    throw const FormatException('通知書の月額を0以上の整数で入力してください');
  }
  return value;
}

List<int?> _displayAmounts(Object? raw) {
  if (raw is! List || raw.length != 12) throw const FormatException('年度の住民税を確認できません');
  return List<int?>.unmodifiable(raw.map((v) => v == null ? null : residentTaxAnnualYen(v)));
}

class ResidentTaxAnnualWorker {
  ResidentTaxAnnualWorker.fromJson(Map raw)
      : id = raw['worker_id'] as String, name = raw['name'] as String,
        currentAmount = residentTaxAnnualYen(raw['current_amount_yen']),
        amounts = List<int>.unmodifiable((raw['amounts'] as List).map(residentTaxAnnualYen)),
        confirmed = raw['confirmed'] as bool, excluded = raw['excluded'] as bool,
        reason = raw['reason'] as String?,
        confirmedAt = raw['confirmed_at'] == null ? null : DateTime.parse(raw['confirmed_at'] as String),
        sourceJson = jsonEncode(raw['source']),
        lastUpdatedAt = raw['last_updated_at'] == null ? null : DateTime.parse(raw['last_updated_at'] as String),
        previousAmounts = _displayAmounts(raw['previous_amounts']),
        currentAmounts = _displayAmounts(raw['current_amounts']),
        undoRequestId = raw['undo_request_id'] as String?,
        undoAmounts = raw['undo_before_amounts'] == null ? null :
          List<int>.unmodifiable((raw['undo_before_amounts'] as List).map(residentTaxAnnualYen));
  final String id, name;
  final int currentAmount;
  final List<int> amounts;
  final bool confirmed, excluded;
  final String? reason;
  final DateTime? confirmedAt;
  final DateTime? lastUpdatedAt;
  final String sourceJson;
  final List<int?> previousAmounts, currentAmounts;
  final String? undoRequestId;
  final List<int>? undoAmounts;
}

class ResidentTaxAnnualData {
  ResidentTaxAnnualData.fromJson(Object? raw, String company, int year) {
    if (raw is! Map || raw['company_id'] != company || raw['fiscal_year'] != year ||
        raw['can_edit'] is! bool || raw['scope_complete'] is! bool ||
        raw['complete'] is! bool || raw['snapshot'] is! Map || raw['workers'] is! List ||
        raw['previous_fiscal_year'] != year - 1 || raw['current_fiscal_year'] != year) {
      throw StateError('住民税の会社・年度を確認できません');
    }
    final seen = <String>{};
    for (final row in raw['workers'] as List) {
      if (row is! Map || row['worker_id'] is! String || !seen.add(row['worker_id'] as String) ||
          row['name'] is! String || row['confirmed'] is! bool || row['excluded'] is! bool ||
          row['reason'] != null && row['reason'] is! String ||
          row['source'] is! Map ||
          row['confirmed_at'] != null && (row['confirmed_at'] is! String || DateTime.tryParse(row['confirmed_at'] as String) == null) ||
          row['amounts'] is! List || (row['amounts'] as List).length != 12) {
        throw const FormatException('従業員の住民税を確認できません');
      }
      workers.add(ResidentTaxAnnualWorker.fromJson(row));
    }
    companyId = company; fiscalYear = year;
    canEdit = raw['can_edit'] == true && raw['scope_complete'] == true;
    scopeComplete = raw['scope_complete'] == true; complete = raw['complete'] == true;
    snapshotJson = jsonEncode(raw['snapshot']);
    receipt = raw['receipt'] is Map ? Map<String, dynamic>.from(raw['receipt'] as Map) : null;
    if (receipt != null && (receipt!['company_id'] != company || receipt!['fiscal_year'] != year ||
        receipt!['request_id'] is! String)) { throw StateError('保存結果の会社・年度が一致しません'); }
  }
  late final String companyId, snapshotJson;
  late final int fiscalYear;
  late final bool canEdit, scopeComplete, complete;
  late final Map<String, dynamic>? receipt;
  final workers = <ResidentTaxAnnualWorker>[];
}

class ResidentTaxAnnualInput {
  ResidentTaxAnnualInput({required this.workerId, required this.amounts,
    required this.excluded, this.reason});
  final String workerId;
  final List<int> amounts;
  final bool excluded;
  final String? reason;
  Map<String, dynamic> toJson() => {'worker_id': workerId, 'amounts': amounts,
    'confirmed': true, 'excluded': excluded, 'reason': reason};
}

abstract class ResidentTaxAnnualRepository {
  Future<ResidentTaxAnnualData> read(String companyId, int fiscalYear, {String? requestId});
  Future<void> save(ResidentTaxAnnualData current, List<ResidentTaxAnnualInput> entries, String requestId);
  Future<void> undo(ResidentTaxAnnualData current, ResidentTaxAnnualWorker worker, String requestId);
}

class ResidentTaxAnnualReloadRequired implements Exception {
  const ResidentTaxAnnualReloadRequired();
}

class SupabaseResidentTaxAnnualRepository implements ResidentTaxAnnualRepository {
  SupabaseResidentTaxAnnualRepository({SupabaseClient? client}) : _providedClient = client;
  final SupabaseClient? _providedClient;
  Future<Object?> _request(String name, Map<String, dynamic> parameters) async {
    final client = _providedClient ?? SupabaseBackend.client;
    final actor = client.auth.currentUser?.id;
    final token = client.auth.currentSession?.accessToken;
    if (actor == null || token == null) throw StateError('ログインを確認してください');
    var revoked = false;
    final subscription = client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != actor || event.session?.accessToken != token) revoked = true;
    }, onError: (Object _) { revoked = true; });
    try {
      final result = await client.rpc(name, params: parameters).setHeader('Authorization', 'Bearer $token');
      if (revoked || client.auth.currentUser?.id != actor || client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました');
      }
      return result;
    } finally { await subscription.cancel(); }
  }
  @override
  Future<ResidentTaxAnnualData> read(String companyId, int fiscalYear, {String? requestId}) async =>
    ResidentTaxAnnualData.fromJson(await _request('read_company_resident_tax_annual', {
      'p_company_id': companyId, 'p_fiscal_year': fiscalYear,
      if (requestId != null) 'p_request_id': requestId,
    }), companyId, fiscalYear);
  @override
  Future<void> save(ResidentTaxAnnualData current, List<ResidentTaxAnnualInput> entries, String requestId) async {
    if (!current.canEdit || entries.length > current.workers.length || entries.isEmpty) {
      throw StateError('従業員の確認が必要です');
    }
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.workerId) || !current.workers.any((w) => w.id == entry.workerId) ||
          entry.amounts.length != 12 || entry.excluded && (entry.reason?.trim().isEmpty ?? true)) {
        throw const FormatException('従業員の確認内容が一致しません');
      }
      entry.amounts.forEach(residentTaxAnnualYen);
      if (entry.excluded) {
        final original = current.workers.singleWhere((w) => w.id == entry.workerId).amounts;
        if (List.generate(12, (i) => i).any((i) => entry.amounts[i] != original[i])) {
          throw const FormatException('対象外の従業員の登録額は変更できません');
        }
      }
    }
    final Object? raw;
    try {
      raw = await _request('save_company_resident_tax_annual', {
        'p_company_id': current.companyId, 'p_fiscal_year': current.fiscalYear,
        'p_expected_snapshot': jsonDecode(current.snapshotJson),
        'p_entries': entries.map((e) => e.toJson()).toList(), 'p_request_id': requestId,
      });
    } on PostgrestException catch (error) {
      if (const {'40001', '22023', '42501', 'PGRST202'}.contains(error.code)) {
        throw const ResidentTaxAnnualReloadRequired();
      }
      rethrow;
    }
    if (raw is! Map || raw['request_id'] != requestId || raw['company_id'] != current.companyId ||
        raw['fiscal_year'] != current.fiscalYear || raw['snapshot'] is! Map) {
      throw StateError('一括保存の結果を確認できません');
    }
  }
  @override
  Future<void> undo(ResidentTaxAnnualData current, ResidentTaxAnnualWorker worker, String requestId) async {
    if (!current.canEdit || worker.undoRequestId == null || worker.undoAmounts?.length != 12) {
      throw StateError('元に戻せる更新を確認できません');
    }
    final Object? raw;
    try {
      raw = await _request('undo_company_resident_tax_annual', {
        'p_company_id': current.companyId, 'p_fiscal_year': current.fiscalYear,
        'p_worker_id': worker.id, 'p_expected_snapshot': jsonDecode(current.snapshotJson),
        'p_undo_request_id': worker.undoRequestId, 'p_request_id': requestId,
      });
    } on PostgrestException catch (error) {
      if (const {'40001', '22023', '42501', 'PGRST202'}.contains(error.code)) throw const ResidentTaxAnnualReloadRequired();
      rethrow;
    }
    if (raw is! Map || raw['request_id'] != requestId || raw['company_id'] != current.companyId ||
        raw['fiscal_year'] != current.fiscalYear || raw['worker_id'] != worker.id || raw['undone'] != true ||
        raw['undo_request_id'] != worker.undoRequestId || raw['snapshot'] is! Map) {
      throw StateError('元に戻した結果を確認できません');
    }
  }
}
