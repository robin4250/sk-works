import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class PaidLeaveSummary {
  const PaidLeaveSummary({
    required this.grantedDays,
    required this.usedDays,
    required this.remainingDays,
  });

  final double grantedDays;
  final double usedDays;
  final double remainingDays;
}

class PaidLeaveRequestRow {
  const PaidLeaveRequestRow({
    required this.id,
    required this.batchId,
    required this.leaveDate,
    required this.status,
    required this.reason,
  });

  final String id;
  final String batchId;
  final DateTime leaveDate;
  final String status;
  final String reason;
}

class PaidLeaveApprovalBatch {
  const PaidLeaveApprovalBatch({
    required this.batchId,
    required this.requestedByName,
    required this.dateCount,
    required this.firstDate,
    required this.lastDate,
    required this.reason,
    this.status = 'pending',
    this.canDecide = true,
    this.leaveDates,
  });

  final String status;
  final bool canDecide;
  final List<DateTime>? leaveDates;
  final String batchId;
  final String requestedByName;
  final int dateCount;
  final DateTime firstDate;
  final DateTime lastDate;
  final String reason;
}

class PaidLeaveRepository {
  PaidLeaveRepository._(this._client);

  final SupabaseClient _client;

  static PaidLeaveRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PaidLeaveRepository._(client);
  }

  Future<PaidLeaveSummary> loadSummary() async {
    final raw = await _client.rpc('paid_leave_my_summary');
    final value =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    return PaidLeaveSummary(
      grantedDays: _number(value['granted_days']),
      usedDays: _number(value['used_days']),
      remainingDays: _number(value['remaining_days']),
    );
  }

  Future<List<PaidLeaveRequestRow>> loadMyRequests() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('paid_leave_requests')
        .select('id,batch_id,leave_date,status,reason')
        .eq('requested_by', user.id)
        .order('leave_date', ascending: false);
    return [
      for (final row in rows)
        PaidLeaveRequestRow(
          id: row['id']?.toString() ?? '',
          batchId: row['batch_id']?.toString() ?? '',
          leaveDate: DateTime.parse(row['leave_date'].toString()),
          status: row['status']?.toString() ?? 'pending',
          reason: row['reason']?.toString() ?? '',
        ),
    ];
  }

  Future<String> submit({
    required Iterable<DateTime> dates,
    String? reason,
  }) async {
    final normalized = dates
        .map((date) => _dbDate(date))
        .toSet()
        .toList(growable: false)
      ..sort();
    Object? raw;
    try {
      raw = await _client.rpc(
        'submit_paid_leave_request',
        params: {
          'p_dates': normalized,
          'p_reason': reason?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw StateError(_paidLeaveErrorMessage(error.message));
    }
    final batchId = raw?.toString() ?? '';
    if (batchId.isEmpty) throw StateError('有給申請を作成できませんでした。');
    return batchId;
  }

  Future<String> submitRetrospective({
    required Iterable<DateTime> dates,
    String? reason,
  }) async {
    final normalized = dates
        .map((date) => _dbDate(date))
        .toSet()
        .toList(growable: false)
      ..sort();
    Object? raw;
    try {
      raw = await _client.rpc(
        'submit_retrospective_paid_leave_request',
        params: {
          'p_dates': normalized,
          'p_reason': reason?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw StateError(_paidLeaveErrorMessage(error.message));
    }
    final batchId = raw?.toString() ?? '';
    if (batchId.isEmpty) {
      throw StateError('有給への勤務修正申請を作成できませんでした。');
    }
    return batchId;
  }

  Future<List<PaidLeaveApprovalBatch>> loadPendingApprovals() async {
    final raw = await _client.rpc('pending_paid_leave_request_batches');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          PaidLeaveApprovalBatch(
            batchId: item['batch_id']?.toString() ?? '',
            requestedByName:
                item['requested_by_name']?.toString() ?? 'SKOユーザー',
            dateCount: (item['date_count'] as num?)?.toInt() ?? 0,
            firstDate: DateTime.parse(item['first_date'].toString()),
            lastDate: DateTime.parse(item['last_date'].toString()),
            reason: item['reason']?.toString() ?? '',
          ),
    ].where((item) => item.batchId.isNotEmpty).toList(growable: false);
  }

  /// Reads exactly the notification's batch using existing SELECT RLS.
  Future<List<PaidLeaveApprovalBatch>> loadApprovalTarget(String batchId) async {
    final rows = await _client
        .from('paid_leave_requests')
        .select('batch_id,leave_date,status,reason,workers(name)')
        .eq('batch_id', batchId)
        .order('leave_date');
    if (rows.isEmpty) return const [];
    var canDecide = false;
    try {
      final pending = await loadPendingApprovals();
      canDecide = pending.any((item) => item.batchId == batchId);
    } on PostgrestException {
      // Applicants can view their own request without approval permission.
    }
    final statuses = rows.map((row) => row['status']?.toString() ?? '').toSet();
    final status = statuses.length == 1 ? statuses.single : 'mixed';
    final worker = rows.first['workers'];
    return [
      PaidLeaveApprovalBatch(
        batchId: batchId,
        requestedByName: worker is Map
            ? worker['name']?.toString() ?? 'SKOユーザー' : 'SKOユーザー',
        dateCount: rows.length,
        firstDate: DateTime.parse(rows.first['leave_date'].toString()),
        lastDate: DateTime.parse(rows.last['leave_date'].toString()),
        reason: rows.first['reason']?.toString() ?? '',
        status: status,
        canDecide: canDecide && status == 'pending',
        leaveDates: List.unmodifiable(rows.map(
          (row) => DateTime.parse(row['leave_date'].toString()),
        )),
      ),
    ];
  }

  Future<List<DateTime>> loadBatchDates(String batchId) async {
    final raw = await _client.rpc(
      'paid_leave_request_dates',
      params: {'p_batch_id': batchId},
    );
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['leave_date'] != null)
          DateTime.parse(item['leave_date'].toString()),
    ];
  }

  Future<String> decide({
    required String batchId,
    required bool approve,
    String? note,
  }) async {
    final raw = await _client.rpc(
      'decide_paid_leave_request',
      params: {
        'p_batch_id': batchId,
        'p_decision': approve ? 'approve' : 'reject',
        'p_note': note?.trim(),
      },
    );
    return raw?.toString() ?? '';
  }

  static String _paidLeaveErrorMessage(String raw) {
    final message = raw.toLowerCase();
    if (message.contains('paid leave balance exceeded')) {
      return '有給残日数が不足しています。個別給与設定の有給付与日数を確認してください。';
    }
    if (message.contains('paid leave already requested')) {
      return '選択した日に、すでに有給申請があります。';
    }
    if (message.contains('attendance exists')) {
      return '選択した日に勤務実績があります。先に通常の勤務修正を行ってください。';
    }
    if (message.contains('future paid leave')) {
      return '未来日の有給は「有給申請」から申請してください。';
    }
    return '有給申請を処理できませんでした。内容を確認してもう一度お試しください。';
  }

  static double _number(Object? value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  static String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
