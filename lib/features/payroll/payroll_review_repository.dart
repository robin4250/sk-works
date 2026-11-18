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
    this.workerId = '',
  });

  /// Identity supplied by the workspace RPC; never infer it from the name.
  final String workerId;
  final PayrollStatementRecord statement;
  final int revision;
  final bool reviewChecked;
  final bool reviewConfirmed;
  final bool reviewerConfirmed;
}

class PayrollDraftRecalculationPreview {
  const PayrollDraftRecalculationPreview._(
    this.grossPay,
    this.deductions,
    this.netPay,
    this._params,
    this._token,
  );

  final int grossPay;
  final int deductions;
  final int netPay;
  final Map<String, dynamic> _params;
  final String _token;
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
    this.rosterIdentitiesComplete = false,
  });

  final bool rosterIdentitiesComplete;

  bool get canCompareRoster =>
      rosterIdentitiesComplete &&
      items.every((item) => _payrollWorkerId(item.workerId).isNotEmpty) &&
      items.map((item) => item.workerId).toSet().length == items.length;

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

  PayrollReviewRepository.forTesting(this._client);

  final SupabaseClient _client;

  static PayrollReviewRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PayrollReviewRepository._(client);
  }

  /// Reads only the target period through the existing statement SELECT RLS.
  /// No wage fields, service credentials or alternate access paths are used.
  Future<DateTime> notificationMonth(String statementId) =>
      resolvePayrollNotificationMonth(statementId, (id) async {
        return await _client
            .from('payroll_statements')
            .select('period_start')
            .eq('id', id)
            .maybeSingle();
      });

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
      rosterIdentitiesComplete:
          value['workers'] is List &&
          value['statements'] is List &&
          statements.every((statement) => statement is Map) &&
          workers.every(
            (worker) =>
                worker is Map && _payrollWorkerId(worker['id']).isNotEmpty,
          ) &&
          workers
                  .map((worker) => _payrollWorkerId((worker as Map)['id']))
                  .toSet()
                  .length ==
              workers.length,
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
              workerId: _payrollWorkerId(rawWorker['id']),
              workerName: rawWorker['name']?.toString() ?? '',
              visibleToManager: rawWorker['visible_to_manager'] == true,
            ),
      ].where((item) => item.workerId.isNotEmpty).toList(growable: false),
    );
  }

  Future<PayrollDraftRecalculationPreview> previewDraftRecalculation(
    PayrollReviewItem item,
  ) async {
    final statement = item.statement;
    final revision = statement.revision;
    final token = _client.auth.currentSession?.accessToken;
    if (!statement.isDraft ||
        revision == null ||
        token == null ||
        _payrollWorkerId(item.workerId).isEmpty) {
      throw StateError('給与下書きの対象を確認できません。');
    }
    final period = statement.periodStart.toIso8601String().split('T').first;
    final params = <String, dynamic>{
      'p_statement_id': statement.id,
      'p_expected_revision': revision,
      'p_worker_id': item.workerId,
      'p_period_start': period,
    };
    final raw = await _client
        .rpc('preview_payroll_review_recalculation', params: params)
        .setHeader('Authorization', 'Bearer $token');
    if (_client.auth.currentSession?.accessToken != token ||
        raw is! Map ||
        raw['contract_version'] != 1 ||
        raw['preview_kind'] != 'current_draft_only' ||
        raw['statement_id'] != statement.id ||
        raw['worker_id'] != item.workerId ||
        raw['period_start'] != period ||
        raw['period_end'] !=
            statement.periodEnd.toIso8601String().split('T').first ||
        raw['expected_revision'] != revision ||
        _payrollWorkerId(raw['company_id']).isEmpty ||
        raw['expected_source'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(raw['expected_source'] as String) ||
        raw['gross_pay'] is! int ||
        raw['deductions'] is! int ||
        raw['net_pay'] is! int) {
      throw const FormatException('給与下書きの事前確認を読み取れません。');
    }
    return PayrollDraftRecalculationPreview._(
      raw['gross_pay'] as int,
      raw['deductions'] as int,
      raw['net_pay'] as int,
      {
        ...params,
        'p_company_id': raw['company_id'],
        'p_expected_source': raw['expected_source'],
        'p_confirmed': true,
      },
      token,
    );
  }

  Future<({bool changed, int revision})> recalculateDraft(
    PayrollDraftRecalculationPreview preview,
  ) async {
    if (_client.auth.currentSession?.accessToken != preview._token) {
      throw StateError('給与下書きの操作中にログイン状態が変わりました。');
    }
    final raw = await _client
        .rpc('recalculate_one_payroll_draft', params: preview._params)
        .setHeader('Authorization', 'Bearer ${preview._token}');
    if (_client.auth.currentSession?.accessToken != preview._token ||
        raw is! Map ||
        raw['contract_version'] != 1 ||
        raw['statement_id'] != preview._params['p_statement_id'] ||
        raw['workflow_state'] != 'draft' ||
        raw['finalized'] != false ||
        raw['revision'] is! int ||
        (raw['revision'] as int) <
            (preview._params['p_expected_revision'] as int) ||
        raw['changed'] is! bool) {
      throw const FormatException('給与下書きの保存結果を確認できません。');
    }
    return (changed: raw['changed'] as bool, revision: raw['revision'] as int);
  }

  Future<void> setManagerVisibility({
    required String workerId,
    required bool visible,
  }) async {
    await _client.rpc(
      'set_payroll_manager_worker_visibility',
      params: {'p_worker_id': workerId, 'p_visible': visible},
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
    return PayrollReviewItem(
      workerId: _payrollWorkerId(row['worker_id']),
      statement: payrollStatementFromRow(row, null, managementBankHidden: true),
      revision: (row['revision'] as num?)?.toInt() ?? 1,
      reviewChecked: row['review_checked'] == true,
      reviewConfirmed: row['review_confirmed'] == true,
      reviewerConfirmed: row['reviewer_confirmed'] == true,
    );
  }
}

Future<DateTime> resolvePayrollNotificationMonth(
  String statementId,
  Future<Map<String, dynamic>?> Function(String id) readVisiblePeriod,
) async {
  final id = statementId.trim();
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
  ).hasMatch(id)) {
    throw StateError('Invalid payroll notification target');
  }
  final row = await readVisiblePeriod(id);
  final date = DateTime.tryParse(row?['period_start']?.toString() ?? '');
  if (date == null) {
    throw StateError('Payroll notification target is unavailable');
  }
  return DateTime(date.year, date.month);
}

String _payrollWorkerId(dynamic value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    return '';
  }
  return value.toLowerCase();
}
