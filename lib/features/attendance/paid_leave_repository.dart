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
  });

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
    final raw = await _client.rpc(
      'submit_paid_leave_request',
      params: {
        'p_dates': normalized,
        'p_reason': reason?.trim(),
      },
    );
    final batchId = raw?.toString() ?? '';
    if (batchId.isEmpty) throw StateError('有給申請を作成できませんでした。');
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

  static double _number(Object? value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  static String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
