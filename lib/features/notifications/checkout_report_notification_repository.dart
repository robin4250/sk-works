import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class CheckoutReportNotificationUnavailable implements Exception {}

const checkoutReportRegistrationAction = 'checkout_report_registration';
const _blockingStates = {'report_missing', 'source_conflict', 'report_input_incomplete', 'reporter_signature_missing', 'report_choice_required'};
const _waitingStates = {'reporter_saved_waiting_supervisor', 'signed_projection_unverified', 'checkout_deferred'};
final _uuid = RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$');

String _id(Object? value) {
  if (value is! String || !_uuid.hasMatch(value)) { throw CheckoutReportNotificationUnavailable(); }
  return value;
}

DateTime _day(Object? value) {
  final date = value is String ? DateTime.tryParse(value) : null;
  if (value is! String || !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(value) ||
      date == null || date.toIso8601String().substring(0, 10) != value) {
    throw CheckoutReportNotificationUnavailable();
  }
  return date;
}

class CheckoutReportNotificationItem {
  CheckoutReportNotificationItem._(Map row)
      : companyId = _id(row['company_id']), workerId = _id(row['worker_id']),
        workDate = _day(row['work_date']), reportId = _id(row['report_id']),
        sourceClockInId = _id(row['source_clock_in_id']), clockOutId = _id(row['clock_out_id']),
        siteId = row['site_id'] == null ? null : _id(row['site_id']),
        routeId = row['route_assignment_id'] == null ? null : _id(row['route_assignment_id']),
        state = row['registration_state'] as String, blocking = row['blocking'] as bool,
        fingerprint = row['scope_fingerprint'] as String;
  final String companyId, workerId, reportId, sourceClockInId, clockOutId, state, fingerprint;
  final String? siteId, routeId;
  final DateTime workDate;
  final bool blocking;
  bool get canResume => const {'report_input_incomplete', 'reporter_signature_missing',
    'reporter_saved_waiting_supervisor', 'signed_projection_unverified'}.contains(state);
}

class CheckoutReportNotificationSnapshot {
  CheckoutReportNotificationSnapshot._(this.reportId, this.enabled, this.resolved, this.items);
  final String reportId;
  final bool enabled, resolved;
  final List<CheckoutReportNotificationItem> items;
  static CheckoutReportNotificationSnapshot parse(Object? raw, {required String actorId, required String reportId}) {
    const keys = {'schema','actor_id','report_id','enforcement_enabled','effective_from','resolved','items'};
    if (raw is! Map || !keys.every(raw.containsKey) || !raw.keys.every((key) => keys.contains(key) || key == 'choice_enforcement_enabled') ||
        raw['schema'] != 1 || raw['actor_id'] != actorId || raw['report_id'] != reportId ||
        !_uuid.hasMatch(actorId) || !_uuid.hasMatch(reportId) ||
        raw['enforcement_enabled'] is! bool || raw['resolved'] is! bool || raw['items'] is! List ||
        (raw['items'] as List).length > 400 || utf8.encode(jsonEncode(raw)).length > 128 * 1024) {
      throw CheckoutReportNotificationUnavailable();
    }
    final enabled = raw['enforcement_enabled'] as bool, resolved = raw['resolved'] as bool;
    if (raw.containsKey('choice_enforcement_enabled') &&
        (raw['choice_enforcement_enabled'] is! bool || raw['choice_enforcement_enabled'] == true && !enabled)) {
      throw CheckoutReportNotificationUnavailable();
    }
    final effective = raw['effective_from'] == null ? null : _day(raw['effective_from']);
    if ((enabled && effective == null) || (resolved && (!enabled || (raw['items'] as List).isNotEmpty))) {
      throw CheckoutReportNotificationUnavailable();
    }
    const itemKeys = {'company_id','worker_id','work_date','site_id','route_assignment_id','report_id',
      'source_clock_in_id','clock_out_id','registration_state','blocking','scope_fingerprint'};
    const choiceKeys = {'choice_available','member_count','report_started'};
    final items = <CheckoutReportNotificationItem>[];
    final seen = <String>{};
    for (final row in raw['items'] as List) {
      if (row is! Map || !itemKeys.every(row.containsKey) || !row.keys.every((key) => itemKeys.contains(key) || choiceKeys.contains(key)) ||
          row['report_id'] != reportId || row['blocking'] is! bool ||
          !_blockingStates.contains(row['registration_state']) && !_waitingStates.contains(row['registration_state']) ||
          row['blocking'] != _blockingStates.contains(row['registration_state']) ||
          row['scope_fingerprint'] is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(row['scope_fingerprint'] as String)) {
        throw CheckoutReportNotificationUnavailable();
      }
      final hasChoice = choiceKeys.any(row.containsKey);
      if (hasChoice && (!choiceKeys.every(row.containsKey) || row['choice_available'] != true ||
          row['report_started'] is! bool || row['member_count'] is! int || row['member_count'] < 1 ||
          raw['choice_enforcement_enabled'] == false)) {
        throw CheckoutReportNotificationUnavailable();
      }
      if (const {'report_choice_required','checkout_deferred'}.contains(row['registration_state']) &&
          (!hasChoice || row['report_started'] != false ||
            row['registration_state'] == 'report_choice_required' && row['member_count'] < 2)) {
        throw CheckoutReportNotificationUnavailable();
      }
      final item = CheckoutReportNotificationItem._(row);
      if ((item.siteId == null) == (item.routeId == null) || item.sourceClockInId == item.clockOutId ||
          !seen.add('${item.companyId}/${item.workerId}/${item.clockOutId}') ||
          enabled && item.workDate.isBefore(effective!) && !(hasChoice && row['report_started'] == true) ||
          items.isNotEmpty && (item.companyId != items.first.companyId || item.workDate != items.first.workDate ||
            item.siteId != items.first.siteId || item.routeId != items.first.routeId)) {
        throw CheckoutReportNotificationUnavailable();
      }
      items.add(item);
    }
    if (enabled && !resolved && items.isEmpty) { throw CheckoutReportNotificationUnavailable(); }
    return CheckoutReportNotificationSnapshot._(reportId, enabled, resolved, List.unmodifiable(items));
  }
}

abstract interface class CheckoutReportNotificationSource {
  String? get sessionKey;
  Stream<String?> get sessionChanges;
  Future<CheckoutReportNotificationSnapshot> load(String reportId);
}

class CheckoutReportNotificationRepository implements CheckoutReportNotificationSource {
  CheckoutReportNotificationRepository(this.client);
  final SupabaseClient client;
  static CheckoutReportNotificationRepository? maybeCreate() =>
    SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
      ? CheckoutReportNotificationRepository(SupabaseBackend.client) : null;
  String? _key(Session? session) {
    if (session == null) { return null; }
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(session.accessToken.split('.')[1]))));
      final sid = claims is Map ? claims['session_id'] : null;
      return sid is String && sid.isNotEmpty ? '${session.user.id}/$sid' : null;
    } catch (_) { return null; }
  }
  @override String? get sessionKey => client.auth.currentSession?.isExpired == false ? _key(client.auth.currentSession) : null;
  @override Stream<String?> get sessionChanges => client.auth.onAuthStateChange.map((event) =>
    event.event == AuthChangeEvent.signedOut ? null : _key(event.session));
  @override Future<CheckoutReportNotificationSnapshot> load(String reportId) async {
    _id(reportId);
    final session = client.auth.currentSession;
    final initial = sessionKey;
    if (session == null || initial == null) { throw CheckoutReportNotificationUnavailable(); }
    var revoked = false;
    final subscription = sessionChanges.listen((event) {
      if (event != initial) { revoked = true; }
    }, onError: (Object _) { revoked = true; });
    void check() {
      if (revoked || sessionKey != initial || client.auth.currentSession?.accessToken != session.accessToken) {
        throw CheckoutReportNotificationUnavailable();
      }
    }
    CheckoutReportNotificationSnapshot result;
    try {
      check();
      final raw = await client.rpc('read_checkout_report_registration_notification', params: {'p_report_id': reportId})
        .setHeader('Authorization', 'Bearer ${session.accessToken}').timeout(const Duration(seconds: 15));
      check();
      result = CheckoutReportNotificationSnapshot.parse(raw, actorId: session.user.id, reportId: reportId);
    } catch (_) { throw CheckoutReportNotificationUnavailable(); }
    finally { await subscription.cancel(); }
    check(); return result;
  }
}
