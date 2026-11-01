import 'dart:async';
import 'package:flutter/foundation.dart';
import '../auth/apple_session_navigation_binding.dart';
import '../shared/trade_document_form_session.dart';
import '../sites/site_order_workflow_repository.dart';
import '../sites/site_order_site_actions.dart' show verifySiteOrderNotificationTarget, SiteOrderNotificationDenied;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'notification_business_status.dart';
import 'source_notification_target.dart';
import 'checkout_report_notification_repository.dart';
import '../payroll/resident_tax_reminder_repository.dart';

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

  bool get hasBusinessTarget => (kind == 'resident_tax_reminder' && actionKey == 'payroll_settings') || const {
    'payroll_review', 'invoice_approval', 'daily_report_edit_request',
    'paid_leave_request', 'worker_personnel_change', 'attendance_correction_request',
    'expense_review_request', 'checkout_report_registration',
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
  /// Isolated client injection; production continues through maybeCreate().
  AppNotificationRepository.forTesting(this._client);

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
        final key = item.kind == 'resident_tax_reminder' ? 'resident-tax:${item.id}' : '${item.actionKey}:${item.actionId}';
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
    if (item.kind == 'resident_tax_reminder' && item.actionKey == 'payroll_settings') {
      try {
        final target = await SupabaseResidentTaxReminderRepository(_client).target(item.id, id, requireWorkspace: false);
        return NotificationBusinessStatus(
          state: target.complete ? NotificationBusinessState.completed : NotificationBusinessState.pending,
          targetName: '${target.fiscalYear}年度 住民税', targetDate: DateTime(target.fiscalYear, 6, 1),
        );
      } catch (_) {return const NotificationBusinessStatus();}
    }
    if (item.actionKey == checkoutReportRegistrationAction) {
      try {
        final target = await CheckoutReportNotificationRepository(_client).load(id);
        return NotificationBusinessStatus(
          state: !target.enabled ? NotificationBusinessState.unknown
              : target.resolved ? NotificationBusinessState.completed : NotificationBusinessState.pending,
          targetDate: target.items.isEmpty ? null : target.items.first.workDate,
        );
      } catch (_) { return const NotificationBusinessStatus(); }
    }
    if (item.actionKey == 'expense_review_request') {
      final actor = _client.auth.currentUser?.id;
      if (actor == null) return const NotificationBusinessStatus();
      try {
        final value = await _client.rpc('expense_notification_target',
            params: {'p_notification_id': item.id});
        if (_client.auth.currentUser?.id != actor) {
          return const NotificationBusinessStatus();
        }
        return expenseNotificationBusinessStatus(
            notificationId: item.id, claimId: item.actionId!, value: value);
      } catch (_) {
        return const NotificationBusinessStatus();
      }
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

  Future<List<AppNotificationRecord>> unreadTargets() async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) throw StateError('Notifications unavailable');
    await _enqueueDueInvoiceApprovals();
    final result = <AppNotificationRecord>[];
    const pageSize = 500;
    for (var offset = 0; ; offset += pageSize) {
      if (_client.auth.currentUser?.id != actor) throw StateError('Account changed');
      final rows = await _client
          .from('app_notifications')
          .select('id,kind,title,body,action_key,action_id,read_at,created_at')
          .eq('recipient_user_id', actor)
          .isFilter('read_at', null)
          .order('id')
          .range(offset, offset + pageSize - 1);
      if (_client.auth.currentUser?.id != actor) throw StateError('Account changed');
      result.addAll(rows.map<AppNotificationRecord>((row) =>
        AppNotificationRecord.fromRow(Map<String, dynamic>.from(row))));
      if (rows.length < pageSize) return result;
    }
  }

  Future<int> unreadCount() async {
    await _enqueueDueInvoiceApprovals();
    final rows = await _client
        .from('app_notifications')
        .select('id')
        .isFilter('read_at', null);
    return rows.length;
  }

  /// Opt-in only. Existing notification marking paths are unchanged.
  SiteOrderNotificationReadScope openSiteOrderReadScope({
    required SiteOrderWorkflowApi api,
    required String notificationId,
    required String packageId,
    String? expectedCompanyId,
    String? Function()? currentCompany,
  }) => SiteOrderNotificationReadScope._(_client, api, notificationId, packageId,
      expectedCompanyId: expectedCompanyId, currentCompany: currentCompany);

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


class SiteOrderNotificationReadUnknown implements Exception {
  const SiteOrderNotificationReadUnknown();
}

/// A RAM-only receipt scope. Cancellation hides stale results; it cannot prove
/// rollback of a read_at update that may already have reached the database.
class SiteOrderNotificationReadScope extends ChangeNotifier {
  SiteOrderNotificationReadScope._(this._client, this.api,
      this.notificationId, this.packageId,
      {String? expectedCompanyId, String? Function()? currentCompany})
      : _expectedCompany = expectedCompanyId,
        _currentCompany = currentCompany {
    if (!_uuid(notificationId) || !_uuid(packageId) ||
        (expectedCompanyId == null) != (currentCompany == null) ||
        (expectedCompanyId != null && !_uuid(expectedCompanyId))) {
      throw const SiteOrderNotificationReadUnknown();
    }
    final captured = _client.auth.currentSession;
    final binding = AppleSessionNavigationBinding.fromSession(captured);
    if (captured == null || binding == null || !api.isNotificationReadClient(_client)) {
      throw const SiteOrderNotificationReadUnknown();
    }
    _captured = captured;
    _binding = binding;
    _session = TradeDocumentFormSession(_client,
      target: expectedCompanyId, currentTarget: currentCompany);
    _session.addListener(_changed);
    api.addListener(_changed);
  }
  static bool _uuid(Object? value) => value is String &&
      RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$').hasMatch(value);
  final SupabaseClient _client;
  final SiteOrderWorkflowApi api;
  final String notificationId, packageId;
  final String? _expectedCompany;
  final String? Function()? _currentCompany;
  late final Session _captured;
  late final AppleSessionNavigationBinding _binding;
  late final TradeDocumentFormSession _session;
  final _retired = Completer<void>();
  String? _company;
  bool _closed = false, _invalid = false, _attempted = false;
  bool get isCurrent {
    try {
      return !_closed && !_invalid && !api.invalidated && !api.uiRetired &&
          identical(_client.auth.currentSession, _captured) &&
          (_currentCompany == null || _currentCompany() == _expectedCompany);
    } catch (_) { return false; }
  }
  void _changed() {
    if (!isCurrent || !_session.isCurrent) retire();
  }
  void retire() {
    if (_invalid || _closed) return;
    _invalid = true;
    if (!_retired.isCompleted) _retired.complete();
    notifyListeners();
  }
  void requireCurrent() {
    if (!isCurrent) { retire(); throw const SiteOrderNotificationReadUnknown(); }
    _session.requireScope();
    api.requireCurrent();
  }
  Future<void> _verify() async {
    if (!isCurrent) throw const SiteOrderNotificationReadUnknown();
    await _session.ready();
    // Admit the API's independent captured session before its synchronous guard.
    if (!isCurrent) throw const SiteOrderNotificationReadUnknown();
    _session.requireScope();
    await api.verify();
    requireCurrent();
    final binding = api.notificationReadBinding;
    if (binding == null || binding.actorId != _binding.actorId ||
        binding.sessionId != _binding.sessionId || !api.isNotificationReadClient(_client)) {
      retire(); throw const SiteOrderNotificationReadUnknown();
    }
    final rows = await _session.readOwnMemberships();
    requireCurrent();
    if (rows is! List || rows.length != 1 || rows.single is! Map) {
      retire(); throw const SiteOrderNotificationReadUnknown();
    }
    final row = rows.single as Map;
    final company = row['company_id'];
    if (!_uuid(company) || company != binding.companyId ||
        !const {'owner', 'admin', 'manager'}.contains(row['role']) ||
        (_company != null && _company != company) ||
        (_expectedCompany != null && _expectedCompany != company)) {
      retire(); throw const SiteOrderNotificationReadUnknown();
    }
    _company ??= company as String;
  }
  void _validateRow(Object? value) {
    if (value is! Map || value.length != 6 ||
        !value.keys.every(const {'id','company_id','recipient_user_id','action_key','action_id','read_at'}.contains) ||
        value['id'] != notificationId || value['company_id'] != _company ||
        value['recipient_user_id'] != _binding.actorId ||
        value['action_key'] != 'site_order_package' || value['action_id'] != packageId ||
        (value['read_at'] != null && (value['read_at'] is! String || DateTime.tryParse(value['read_at']) == null))) {
      throw const SiteOrderNotificationReadUnknown();
    }
  }
  Future<Map<String, dynamic>> _readRow() async {
    final value = await _client.from('app_notifications')
      .select('id,company_id,recipient_user_id,action_key,action_id,read_at')
      .eq('id', notificationId).eq('company_id', _company!)
      .eq('recipient_user_id', _binding.actorId)
      .eq('action_key', 'site_order_package').eq('action_id', packageId)
      .maybeSingle().setHeader('Authorization', 'Bearer ${_captured.accessToken}')
      .abortSignal(_retired.future);
    requireCurrent(); _validateRow(value);
    return Map<String, dynamic>.from(value as Map);
  }
  Future<void> verifyTarget() async {
    try {
      await _verify();
      await verifySiteOrderNotificationTarget(api, packageId);
      requireCurrent();
      await _readRow();
      await _verify();
    } on SiteOrderNotificationDenied { retire(); rethrow; }
    catch (_) { retire(); throw const SiteOrderNotificationReadUnknown(); }
  }
  Future<void> markRead(VoidCallback requireOwnedScope) async {
    if (_attempted) throw const SiteOrderNotificationReadUnknown();
    _attempted = true; // Reserve synchronously before any async admission.
    requireOwnedScope();
    await verifyTarget();
    requireOwnedScope(); requireCurrent();
    final before = await _readRow();
    requireOwnedScope(); requireCurrent();
    // A verified existing read is read-only. Never infer this from a CAS0.
    if (before['read_at'] != null) {
      await _verify();
      await verifySiteOrderNotificationTarget(api, packageId);
      requireOwnedScope(); requireCurrent();
      return;
    }
    try {
      final Object rows = await _client.from('app_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId).eq('company_id', _company!)
        .eq('recipient_user_id', _binding.actorId)
        .eq('action_key', 'site_order_package').eq('action_id', packageId)
        .isFilter('read_at', null)
        .select('id,company_id,recipient_user_id,action_key,action_id,read_at')
        .setHeader('Authorization', 'Bearer ${_captured.accessToken}')
        .abortSignal(_retired.future);
      requireOwnedScope(); requireCurrent();
      await _verify();
      await verifySiteOrderNotificationTarget(api, packageId);
      requireOwnedScope(); requireCurrent();
      if (rows is! List || rows.length != 1) throw const SiteOrderNotificationReadUnknown();
      _validateRow(rows.single);
      if ((rows.single as Map)['read_at'] == null) throw const SiteOrderNotificationReadUnknown();
    } catch (_) {
      // The write may have committed. Retain unknown and never retry it here.
      throw const SiteOrderNotificationReadUnknown();
    }
  }
  @override void dispose() {
    if (_closed) return;
    retire();
    _closed = true;
    _session.removeListener(_changed);
    api.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }
}
