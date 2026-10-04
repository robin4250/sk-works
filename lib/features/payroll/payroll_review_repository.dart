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
    required this.reviewChecked,
    required this.reviewConfirmed,
    required this.reviewerConfirmed,
  });

  final PayrollStatementRecord statement;
  final int revision;
  final bool reviewChecked;
  final bool reviewConfirmed;
  final bool reviewerConfirmed;
}

class PayrollReviewWorkspace {
  const PayrollReviewWorkspace({
    required this.role,
    required this.companyName,
    required this.isAdmin,
    required this.canConfirm,
    required this.periodStart,
    required this.items,
    required this.workers,
  });

  final String role;
  final String companyName;
  final bool isAdmin;
  final bool canConfirm;
  final DateTime periodStart;
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

  Future<PayrollReviewWorkspace> loadWorkspace(DateTime month) async {
    final periodStart =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
    final raw = await _client.rpc(
      'payroll_review_workspace',
      params: {'p_period_start': periodStart},
    );
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
      companyName: value['company_name']?.toString() ?? '',
      isAdmin: value['is_admin'] == true,
      canConfirm: value['can_confirm'] == true,
      periodStart:
          DateTime.tryParse(value['period_start']?.toString() ?? '') ??
              DateTime(month.year, month.month),
      items: [
        for (final rawItem in statements)
          if (rawItem is Map) _item(Map<String, dynamic>.from(rawItem)),
      ],
      workers: [
        for (final rawWorker in workers)
          if (rawWorker is Map)
            PayrollReviewWorkerVisibility(
              workerId: rawWorker['id']?.toString() ?? '',
              workerName: rawWorker['name']?.toString() ?? '',
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
      'set_payroll_manager_worker_visibility',
      params: {
        'p_worker_id': workerId,
        'p_visible': visible,
      },
    );
  }

  Future<void> setReviewCheck({
    required String statementId,
    required int revision,
    required bool checked,
  }) async {
    await _client.rpc(
      'set_payroll_review_check',
      params: {
        'p_statement_id': statementId,
        'p_revision': revision,
        'p_checked': checked,
      },
    );
  }

  Future<int> confirmMonth(DateTime month) async {
    final periodStart =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
    final raw = await _client.rpc(
      'confirm_payroll_review_month',
      params: {'p_period_start': periodStart},
    );
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  PayrollReviewItem _item(Map<String, dynamic> row) {
    final periodStart =
        DateTime.tryParse(row['period_start']?.toString() ?? '') ??
            DateTime.now();
    final periodEnd =
        DateTime.tryParse(row['period_end']?.toString() ?? '') ??
            DateTime.now();

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
      ),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      reviewChecked: row['review_checked'] == true,
      reviewConfirmed: row['review_confirmed'] == true,
      reviewerConfirmed: row['reviewer_confirmed'] == true,
    );
  }
}
