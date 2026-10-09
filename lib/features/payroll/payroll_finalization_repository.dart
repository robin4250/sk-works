import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';
import 'payroll_statement_repository.dart';

typedef PayrollFinalizationRpc = Future<dynamic> Function(String name, Map<String, dynamic> params);

Map<String, dynamic> _object(dynamic raw) {
  if (raw is! Map) throw const FormatException('給与確定の応答を確認できません');
  return Map<String, dynamic>.from(raw);
}
DateTime _day(dynamic raw) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    throw const FormatException('対象期間を確認できません');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || raw != _date(parsed)) throw const FormatException('対象期間を確認できません');
  return parsed;
}
String _date(DateTime day) => '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
int _revision(dynamic raw) {
  final value = strictPayrollRevision(raw);
  if (value == null) throw const FormatException('給与の版を確認できません');
  return value;
}
class PayrollFinalizationStatus {
  const PayrollFinalizationStatus({required this.revision, required this.canFinalize,
    required this.snapshotSaved, required this.workflowState});
  final int revision;
  final bool canFinalize;
  final bool snapshotSaved;
  final String workflowState;
  factory PayrollFinalizationStatus.parse(dynamic raw, PayrollStatementRecord statement) {
    final row = _object(raw);
    if (row['contract_version'] != 1 || row['statement_id'] != statement.id ||
      _day(row['period_start']) != statement.periodStart || _day(row['period_end']) != statement.periodEnd ||
      row['can_finalize'] is! bool || row['snapshot_saved'] is! bool || row['workflow_state'] is! String) {
      throw const FormatException('給与確定の対象を確認できません');
    }
    return PayrollFinalizationStatus(revision: _revision(row['revision']),
      canFinalize: row['can_finalize'] == true, snapshotSaved: row['snapshot_saved'] == true,
      workflowState: row['workflow_state'] as String);
  }
}
class PayrollFinalizationResult {
  const PayrollFinalizationResult({required this.revision, this.statement});
  final int revision;
  final PayrollStatementRecord? statement;
  bool get finalized => statement != null;
  factory PayrollFinalizationResult.parse(dynamic raw, PayrollStatementRecord expected, int revision) {
    final response = _object(raw);
    final returnedRevision = _revision(response['revision']);
    if (response['finalized'] == false && response['reason'] == 'recalculation_changed' &&
        returnedRevision != revision && response['snapshot'] == null) {
      return PayrollFinalizationResult(revision: returnedRevision);
    }
    final snapshot = _object(response['snapshot']);
    final result = _object(snapshot['result']);
    final detail = _object(snapshot['detail']);
    if (response['finalized'] != true || returnedRevision != revision ||
        snapshot['schema_version'] != 1 || snapshot['statement_id'] != expected.id ||
        _revision(snapshot['revision']) != revision ||
        _day(snapshot['period_start']) != expected.periodStart || _day(snapshot['period_end']) != expected.periodEnd ||
        snapshot['company_name'] is! String || snapshot['worker_name'] is! String ||
        detail['workflow_state'] != 'finalized' || detail['review_confirmed'] != true ||
        _revision(detail['revision']) != revision || _object(detail['bank_account']).isNotEmpty ||
        result['gross_pay'] is! int || result['deductions'] is! int || result['net_pay'] is! int ||
        result['gross_pay'] - result['deductions'] != result['net_pay']) {
      throw const FormatException('保存した給与明細を確認できません');
    }
    DateTime? issued;
    if (snapshot['issued_at'] != null) {
      if (snapshot['issued_at'] is! String || (issued = DateTime.tryParse(snapshot['issued_at'] as String)) == null) {
        throw const FormatException('保存した発行日を確認できません');
      }
    }
    return PayrollFinalizationResult(revision: revision, statement: PayrollStatementRecord(
      id: expected.id, companyName: snapshot['company_name'] as String,
      workerName: snapshot['worker_name'] as String, periodStart: _day(snapshot['period_start']),
      periodEnd: _day(snapshot['period_end']), grossPay: result['gross_pay'] as int,
      deductions: result['deductions'] as int, netPay: result['net_pay'] as int,
      detail: detail, issuedAt: issued, reviewConfirmed: true, workflowState: 'finalized',
      revision: revision, reviewedAt: DateTime.tryParse(detail['reviewed_at']?.toString() ?? '')));
  }
}
class PayrollFinalizationRepository {
  PayrollFinalizationRepository({required PayrollFinalizationRpc invoke}) : _invoke = invoke;
  final PayrollFinalizationRpc _invoke;
  static PayrollFinalizationRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null) return null;
    return PayrollFinalizationRepository(invoke: (name, params) async =>
      SupabaseBackend.client.rpc(name, params: params));
  }
  Future<PayrollFinalizationStatus?> read(PayrollStatementRecord statement) async {
    try {
      final raw = await _invoke('read_payroll_finalization_status', {'p_statement_id': statement.id});
      return PayrollFinalizationStatus.parse(raw, statement);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || (error.code == '42883' && error.message.contains('read_payroll_finalization_status'))) return null;
      rethrow;
    }
  }
  Future<PayrollFinalizationResult> finalize(PayrollStatementRecord statement, int revision) async {
    final raw = await _invoke('finalize_payroll_statement', {
      'p_statement_id': statement.id, 'p_expected_revision': revision, 'p_confirmed': true});
    return PayrollFinalizationResult.parse(raw, statement, revision);
  }
}
