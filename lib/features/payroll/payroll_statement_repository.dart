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
    final workerId = await _client.rpc('ensure_current_user_worker');
    final workerIdText = workerId?.toString();
    if (workerIdText == null || workerIdText.isEmpty) {
      throw StateError('本人の作業員情報を確認できません。');
    }

    final rows = await _client
        .from('payroll_statements')
        .select(
          'id, period_start, period_end, gross_pay, deductions, net_pay, detail, issued_at, companies(name), workers(name)',
        )
        .eq('worker_id', workerIdText)
        .order('period_end', ascending: false);

    return rows.map<PayrollStatementRecord>((raw) {
      final row = Map<String, dynamic>.from(raw);
      final company = row['companies'];
      final worker = row['workers'];
      return PayrollStatementRecord(
        id: row['id']?.toString() ?? '',
        companyName:
            company is Map ? company['name']?.toString() ?? '' : '',
        workerName:
            worker is Map ? worker['name']?.toString() ?? '' : '',
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
    }).toList();
  }
}
