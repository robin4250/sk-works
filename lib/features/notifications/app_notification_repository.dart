import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'notification_business_status.dart';
import 'source_notification_target.dart';

class AppNotificationRecord {
  const AppNotificationRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.actionKey,
    this.actionId,
    this.businessStatus = const NotificationBusinessStatus(),
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? actionKey;
  final String? actionId;
  final NotificationBusinessStatus businessStatus;

  bool get hasBusinessTarget => const {
    'payroll_review', 'invoice_approval', 'daily_report_edit_request',
    'paid_leave_request', 'worker_personnel_change', 'attendance_correction_request',
  }.contains(actionKey);

  AppNotificationRecord withBusinessStatus(NotificationBusinessStatus status) =>
      AppNotificationRecord(id: id, kind: kind, title: title, body: body,
        createdAt: createdAt, read: read, actionKey: actionKey,
        actionId: actionId, businessStatus: status);

  factory AppNotificationRecord.fromRow(Map<String, dynamic> row) {
    return AppNotificationRecord(
      id: row['id']?.toString() ?? '',
      kind: row['kind']?.toString() ?? 'info',
      title: row['title']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: row['read_at'] != null,
      actionKey: row['action_key']?.toString(),
      actionId: row['action_id']?.toString(),
    );
  }
}

class AppNotificationRepository {
  AppNotificationRepository._(this._client);

  final SupabaseClient _client;

  static AppNotificationRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AppNotificationRepository._(client);
  }

  Future<List<AppNotificationRecord>> load({int limit = 100}) async {
    await _enqueueDueInvoiceApprovals();
    final rows = await _client
        .from('app_notifications')
        .select(
          'id, kind, title, body, action_key, action_id, read_at, created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    final notifications = rows
        .map<AppNotificationRecord>(
          (row) => AppNotificationRecord.fromRow(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
    final statuses = <String, Future<NotificationBusinessStatus>>{};
    final payrollMonths = <String, Future<dynamic>>{};
    final result = List<AppNotificationRecord>.of(notifications);
    var nextIndex = 0;
    Future<void> enrichNext() async {
      while (nextIndex < notifications.length) {
        final index = nextIndex++;
        final item = notifications[index];
        if (!item.hasBusinessTarget) continue;
        final key = '${item.actionKey}:${item.actionId}';
        final status = await statuses.putIfAbsent(
          key, () => _businessStatus(item, payrollMonths),
        );
        result[index] = item.withBusinessStatus(status);
      }
    }
    await Future.wait(List.generate(
      notifications.length < 6 ? notifications.length : 6,
      (_) => enrichNext(),
    ));
    return result;
  }

  Future<NotificationBusinessStatus> _businessStatus(
    AppNotificationRecord item,
    Map<String, Future<dynamic>> payrollMonths,
  ) async {
    final id = item.actionId?.trim() ?? '';
    if (!RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$').hasMatch(id)) {
      return const NotificationBusinessStatus();
    }
    final source = switch (item.actionKey) {
      'paid_leave_request' => ('paid_leave_requests', 'batch_id', 'status,leave_date,workers(name)'),
      'daily_report_edit_request' => ('daily_report_edit_requests', 'id', 'status'),
      'worker_personnel_change' => ('worker_personnel_change_requests', 'id', 'status,workers(name)'),
      'attendance_correction_request' => ('attendance_correction_requests', 'id', 'status'),
      'invoice_approval' => ('invoices', 'id', 'approval_finalized_at,billing_period_start'),
      'payroll_review' => ('payroll_statements', 'id', 'period_start,workers(name)'),
      _ => null,
    };
    if (source == null) return const NotificationBusinessStatus();
    try {
      final raw = await _client.from(source.$1).select(source.$3).eq(source.$2, id);
      final rows = raw.map((row) => Map<String, dynamic>.from(row)).toList();
      if (item.actionKey == 'invoice_approval') {
        // Only a server finalization timestamp proves overall completion.
        for (final row in rows) {
          if (row['approval_finalized_at'] != null) row['status'] = 'approved';
        }
      }
      if (item.actionKey == 'payroll_review' && rows.length == 1) {
        final period = rows.single['period_start']?.toString();
        if (period != null && DateTime.tryParse(period) != null) {
          try {
            final value = await payrollMonths.putIfAbsent(period, () async =>
                await _client.rpc('payroll_confirmation_status',
                    params: {'p_period_start': period}));
            final state = payrollNotificationState(
              expectedPeriod: period,
              currentUserId: _client.auth.currentUser?.id,
              value: value,
            );
            rows.single['status'] = switch (state) {
              NotificationBusinessState.completed => 'approved',
              NotificationBusinessState.pending => 'pending',
              _ => null,
            };
          } catch (_) {
            // Preserve visible target metadata when completion is unavailable.
          }
        }
      }
      return NotificationBusinessStatus.fromRows(rows);
    } catch (_) {
      // Missing grants, RLS invisibility and old schemas are not pending work.
      // A failed enrichment must never remove the notification itself.
      return const NotificationBusinessStatus();
    }
  }

  Future<SourceNotificationTarget> sourceTarget(AppNotificationRecord item) async {
    if (!SourceNotificationTarget.supports(item.actionKey) || item.id.isEmpty || item.actionId == null) {
      throw const FormatException('Source notification unavailable');
    }
    final userId = _client.auth.currentUser?.id;
    final result = await _client.rpc('get_source_notification_target',
      params: {'p_notification_id': item.id});
    if (userId == null || _client.auth.currentUser?.id != userId) {
      throw StateError('Account changed');
    }
    return SourceNotificationTarget.parse(result, expectedKey: item.actionKey!,
      expectedSourceId: item.actionId!);
  }

  Future<int> unreadCount() async {
    await _enqueueDueInvoiceApprovals();
    final rows = await _client
        .from('app_notifications')
        .select('id')
        .isFilter('read_at', null);
    return rows.length;
  }

  Future<void> markRead(String id) async {
    if (id.isEmpty) return;
    await _client
        .from('app_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> markAllRead() async {
    await _client.rpc('mark_all_notifications_read');
  }

  Future<void> _enqueueDueInvoiceApprovals() async {
    try {
      await _client.rpc('enqueue_due_invoice_approval_notifications');
    } catch (_) {
      // Older schemas remain readable while migrations roll out.
    }
  }
}
