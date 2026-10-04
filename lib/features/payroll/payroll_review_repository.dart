import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'payroll_statement_repository.dart';

class PayrollReviewWorkerVisibility {
  const PayrollReviewWorkerVisibility({
    required this.workerId,
    required this.workerName,
    required this.visibleToManager,
  });

  final String workerId;
  final String workerName;
  final bool visibleToManager;
}

class PayrollReviewItem {
  const PayrollReviewItem({
    required this.statement,
    required this.revision,
    required this.confirmed,
    this.reviewedAt,
  });

  final PayrollStatementRecord statement;
  final int revision;
  final bool confirmed;
  final DateTime? reviewedAt;
}

class PayrollReviewWorkspace {
  const PayrollReviewWorkspace({
    required this.role,
    required this.canManageVisibility,
    required this.canConfirm,
    required this.items,
    required this.workers,
  });

  final String role;
  final bool canManageVisibility;
  final bool canConfirm;
  final List<PayrollReviewItem> items;
  final List<PayrollReviewWorkerVisibility> workers;
}

class PayrollReviewRepository {
  PayrollReviewRepository._(this._client);

  final SupabaseClient _client;

  static PayrollReviewRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PayrollReviewRepository._(client);
  }

  Future<PayrollReviewWorkspace> loadWorkspace() async {
    final raw = await _client.rpc('payroll_review_workspace');
    final value = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};

    final statements = value['statements'] is List
        ? value['statements'] as List<dynamic>
        : const <dynamic>[];
    final workers = value['workers'] is List
        ? value['workers'] as List<dynamic>
        : const <dynamic>[];

    return PayrollReviewWorkspace(
      role: value['role']?.toString() ?? '',
      canManageVisibility: value['can_manage_visibility'] == true,
      canConfirm: value['can_confirm'] == true,
      items: [
        for (final rawItem in statements)
          if (rawItem is Map) _item(Map<String, dynamic>.from(rawItem)),
      ],
      workers: [
        for (final rawWorker in workers)
          if (rawWorker is Map)
            PayrollReviewWorkerVisibility(
              workerId: rawWorker['worker_id']?.toString() ?? '',
              workerName: rawWorker['worker_name']?.toString() ?? '',
              visibleToManager: rawWorker['visible_to_manager'] == true,
            ),
      ].where((item) => item.workerId.isNotEmpty).toList(growable: false),
    );
  }

  Future<void> setManagerVisibility({
    required String workerId,
    required bool visible,
  }) async {
    await _client.rpc(
      'set_payroll_worker_visibility',
      params: {
        'p_worker_id': workerId,
        'p_visible': visible,
      },
    );
  }

  Future<int> confirmMonth({
    required DateTime month,
    required List<String> statementIds,
  }) async {
    final date =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
    final raw = await _client.rpc(
      'confirm_payroll_review',
      params: {
        'p_period_start': date,
        'p_statement_ids': statementIds,
      },
    );
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  PayrollReviewItem _item(Map<String, dynamic> row) {
    final periodStart =
        DateTime.tryParse(row['period_start']?.toString() ?? '') ?? DateTime.now();
    final periodEnd =
        DateTime.tryParse(row['period_end']?.toString() ?? '') ?? DateTime.now();

    return PayrollReviewItem(
      statement: PayrollStatementRecord(
        id: row['id']?.toString() ?? '',
        companyName: '',
        workerName: row['worker_name']?.toString() ?? '',
        periodStart: periodStart,
        periodEnd: periodEnd,
        grossPay: (row['gross_pay'] as num?)?.toInt() ?? 0,
        deductions: (row['deductions'] as num?)?.toInt() ?? 0,
        netPay: (row['net_pay'] as num?)?.toInt() ?? 0,
        detail: row['detail'] is Map
            ? Map<String, dynamic>.from(row['detail'] as Map)
            : const {},
        issuedAt:
            DateTime.tryParse(row['issued_at']?.toString() ?? '')?.toLocal(),
      ),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      confirmed: row['confirmed'] == true,
      reviewedAt:
          DateTime.tryParse(row['reviewed_at']?.toString() ?? '')?.toLocal(),
    );
  }
}
