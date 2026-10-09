import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class PayrollStatementRecord {
  const PayrollStatementRecord({
    required this.id,
    required this.companyName,
    required this.workerName,
    required this.periodStart,
    required this.periodEnd,
    required this.grossPay,
    required this.deductions,
    required this.netPay,
    required this.detail,
    this.issuedAt,
    this.reviewConfirmed = false,
    this.reviewedAt,
    this.workflowState,
  });

  final String? workflowState;
  bool get isDraft => workflowState == 'draft';

  final String id;
  final String companyName;
  final String workerName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int grossPay;
  final int deductions;
  final int netPay;
  final Map<String, dynamic> detail;
  final DateTime? issuedAt;
  final bool reviewConfirmed;
  final DateTime? reviewedAt;

  String get monthLabel => '${periodEnd.year}年${periodEnd.month}月';
}

class PayrollStatementRepository {
  PayrollStatementRepository._(this._client);

  final SupabaseClient _client;

  static PayrollStatementRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PayrollStatementRepository._(client);
  }

  Future<List<PayrollStatementRecord>> loadMyStatements() async {
    final rows = await _client.rpc(
      'my_payroll_statement_rows_with_adjustments',
    );

    final statusById = <String, Map<String, dynamic>>{};
    try {
      final statusRows = await _client.rpc('my_payroll_review_statuses');
      if (statusRows is List) {
        for (final raw in statusRows) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final id = row['statement_id']?.toString() ?? '';
          if (id.isNotEmpty) statusById[id] = row;
        }
      }
    } catch (_) {
      // Keep payroll statements available while review-status migration rolls out.
    }

    return [
      for (final raw in (rows as List<dynamic>))
        if (raw is Map)
          payrollStatementFromRow(
            Map<String, dynamic>.from(raw),
            statusById[raw['id']?.toString() ?? ''],
          ),
    ];
  }

}

String savedPayrollCompanyName(Map<String, dynamic> row,
    Map<String, dynamic> detail) {
  final name = row['company_name']?.toString() ?? '';
  return name.trim().isNotEmpty
      ? name
      : detail['company_name']?.toString() ?? '';
}

PayrollStatementRecord payrollStatementFromRow(
  Map<String, dynamic> row,
  Map<String, dynamic>? review,
) {
  final detail = row['detail'] is Map
      ? Map<String, dynamic>.from(row['detail'] as Map)
      : const <String, dynamic>{};
  final workflowState = row['workflow_state']?.toString() ??
      detail['workflow_state']?.toString();
  return PayrollStatementRecord(
    workflowState: workflowState,
    id: row['id']?.toString() ?? '',
    companyName: savedPayrollCompanyName(row, detail),
    workerName: row['worker_name']?.toString() ?? '',
    periodStart: DateTime.tryParse(row['period_start']?.toString() ?? '') ??
        DateTime.now(),
    periodEnd: DateTime.tryParse(row['period_end']?.toString() ?? '') ??
        DateTime.now(),
    grossPay: (row['gross_pay'] as num?)?.toInt() ?? 0,
    deductions: (row['deductions'] as num?)?.toInt() ?? 0,
    netPay: (row['net_pay'] as num?)?.toInt() ?? 0,
    detail: detail,
    issuedAt: DateTime.tryParse(row['issued_at']?.toString() ?? '')?.toLocal(),
    reviewedAt: DateTime.tryParse(row['reviewed_at']?.toString() ??
        detail['reviewed_at']?.toString() ?? ''),
    reviewConfirmed: workflowState == 'draft'
        ? review?['review_confirmed'] == true
        : row['review_confirmed'] == true || detail['review_confirmed'] == true,
  );
}

/// Current month confirmation can describe drafts, never replace saved history.
PayrollStatementRecord payrollStatementWithDraftReview(
  PayrollStatementRecord original, {
  bool? confirmed,
  String draftCompanyName = '',
}) {
  if (!original.isDraft || confirmed == null) {
    return original;
  }
  return PayrollStatementRecord(
    id: original.id,
    companyName: original.companyName.isEmpty
        ? draftCompanyName
        : original.companyName,
    workerName: original.workerName,
    periodStart: original.periodStart,
    periodEnd: original.periodEnd,
    grossPay: original.grossPay,
    deductions: original.deductions,
    netPay: original.netPay,
    detail: original.detail,
    issuedAt: original.issuedAt,
    reviewConfirmed: confirmed,
    reviewedAt: original.reviewedAt,
    workflowState: original.workflowState,
  );
}
