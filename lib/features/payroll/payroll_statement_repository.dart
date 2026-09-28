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
  });

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

    return [
      for (final raw in (rows as List<dynamic>))
        _fromRow(Map<String, dynamic>.from(raw as Map)),
    ];
  }

  PayrollStatementRecord _fromRow(Map<String, dynamic> row) {
    return PayrollStatementRecord(
      id: row['id']?.toString() ?? '',
      companyName: row['company_name']?.toString() ?? '',
      workerName: row['worker_name']?.toString() ?? '',
      periodStart:
          DateTime.tryParse(row['period_start']?.toString() ?? '') ??
              DateTime.now(),
      periodEnd: DateTime.tryParse(row['period_end']?.toString() ?? '') ??
          DateTime.now(),
      grossPay: (row['gross_pay'] as num?)?.toInt() ?? 0,
      deductions: (row['deductions'] as num?)?.toInt() ?? 0,
      netPay: (row['net_pay'] as num?)?.toInt() ?? 0,
      detail: row['detail'] is Map
          ? Map<String, dynamic>.from(row['detail'] as Map)
          : const {},
      issuedAt:
          DateTime.tryParse(row['issued_at']?.toString() ?? '')?.toLocal(),
    );
  }
}
