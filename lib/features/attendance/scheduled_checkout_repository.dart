import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class ScheduledCheckoutTarget {
  const ScheduledCheckoutTarget({required this.companyId, required this.workerId,
    required this.sourceId, required this.workDate, required this.reminderAt,
    required this.due, required this.scopeFingerprint, required this.canManageAttendance,
    this.siteId, this.routeId});
  final String companyId, workerId, sourceId, workDate, scopeFingerprint;
  final String? siteId, routeId;
  final DateTime reminderAt;
  final bool due, canManageAttendance;
}

@immutable
class ScheduledCheckoutState {
  const ScheduledCheckoutState({required this.actorId, required this.enabled,
    required this.serverTime, required this.targets});
  final String actorId;
  final bool enabled;
  final DateTime serverTime;
  final List<ScheduledCheckoutTarget> targets;
  List<ScheduledCheckoutTarget> get due => targets.where((v) => v.due).toList(growable: false);
}

@immutable
class GpsWorkScheduleConfiguration {
  const GpsWorkScheduleConfiguration({required this.companyId, required this.workerId,
    required this.weekdays, required this.clockInTime, required this.checkoutTime,
    required this.checkoutNextDay, required this.revision, required this.enabled,
    required this.timezone, this.siteId, this.routeId});
  final String companyId, workerId, clockInTime, checkoutTime, timezone;
  final String? siteId, routeId;
  final List<int> weekdays;
  final bool checkoutNextDay, enabled;
  final int revision;
}
@immutable
class ScheduledCheckoutNotification {
  const ScheduledCheckoutNotification({required this.sourceId, required this.workerId,
    required this.workDate, required this.fireAt, this.sourceClockInId});
  final String sourceId, workerId, workDate;
  final String? sourceClockInId;
  final DateTime fireAt;
}
@immutable
class ScheduledCheckoutNotificationPlan {
  const ScheduledCheckoutNotificationPlan({required this.actorId, required this.configurations,
    required this.state, required this.plannedNotifications});
  final String actorId;
  final List<GpsWorkScheduleConfiguration> configurations;
  final ScheduledCheckoutState state;
  final List<ScheduledCheckoutNotification> plannedNotifications;
}

/// Server state, rather than local clock/navigation/notification, decides whether
/// a real clock-in requires checkout confirmation. This class never clocks out.
class ScheduledCheckoutRepository {
  ScheduledCheckoutRepository(this.client);
  final SupabaseClient client;
  String? get actorId => client.auth.currentUser?.id;

  Future<ScheduledCheckoutState> read() => _call('read_my_scheduled_checkout');
  Future<ScheduledCheckoutState> postpone(ScheduledCheckoutTarget target) =>
      _call('postpone_my_scheduled_checkout', params: {
        'p_source_clock_in_id': target.sourceId,
        'p_expected_scope': target.scopeFingerprint,
      });

  Future<ScheduledCheckoutNotificationPlan> loadNotificationPlan() async {
    final actor = actorId;
    final raw = await _guarded(() => client.rpc('read_my_scheduled_checkout_notification_plan'));
    if (actor == null) { throw StateError('ログイン状態を確認してください。'); }
    return parseNotificationPlan(raw, actor);
  }

  Future<void> disable() async {
    await _guarded(() => client.rpc('disable_my_gps_work_schedule'));
  }

  Future<Map<String, dynamic>> save({String? siteId, String? routeId,
    required List<int> weekdays, required String clockInTime,
    required String checkoutTime, required int expectedRevision}) async {
    final actor = actorId;
    final raw = await _guarded(() => client.rpc('save_my_gps_work_schedule', params: {
      'p_site_id': siteId, 'p_route_assignment_id': routeId,
      'p_weekdays': weekdays, 'p_clock_in_time': clockInTime,
      'p_checkout_time': checkoutTime, 'p_expected_revision': expectedRevision,
    }));
    if (raw is! Map || raw['schema'] != 1 || raw['actor_id'] != actor ||
        raw['revision'] is! int || raw['checkout_next_day'] is! bool) {
      throw StateError('出退勤時刻の保存結果を確認できません。');
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<ScheduledCheckoutState> _call(String rpc, {Map<String, dynamic>? params}) async {
    final actor = actorId;
    final raw = await _guarded(() => client.rpc(rpc, params: params));
    if (actor == null) { throw StateError('ログイン状態を確認してください。'); }
    return parse(raw, actor);
  }

  String? get currentSessionIdentity => sessionIdentityOf(client.auth.currentSession);
  static String? sessionIdentityOf(Session? session) {
    if (session == null) { return null; }
    try {
      final parts = session.accessToken.split('.');
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final sid = claims is Map ? claims['session_id'] : null;
      return sid is String && sid.isNotEmpty ? '${session.user.id}/$sid' : null;
    } catch (_) { return null; }
  }

  Future<Object?> _guarded(Future<Object?> Function() operation) async {
    final actor = actorId;
    final key = sessionIdentityOf(client.auth.currentSession);
    if (actor == null || key == null) { throw StateError('ログイン状態を確認してください。'); }
    var changed = false;
    final subscription = client.auth.onAuthStateChange.listen((event) {
      if (sessionIdentityOf(event.session) != key) { changed = true; }
    });
    try {
      final result = await operation();
      // The SDK auth event stream is asynchronous. Keep emitted session identity
      // until queued events have been observed, including A -> B -> A changes.
      await Future<void>.delayed(Duration.zero);
      if (changed || actorId != actor || sessionIdentityOf(client.auth.currentSession) != key) {
        throw StateError('ログイン状態が変わりました。もう一度確認してください。');
      }
      return result;
    } finally { await subscription.cancel(); }
  }

  @visibleForTesting
  static ScheduledCheckoutNotificationPlan parseNotificationPlan(Object? raw, String actor) {
    if (raw is! Map || raw['schema'] != 1 || raw['actor_id'] != actor || raw['planned_notifications'] is! List) {
      throw StateError('退勤通知の予定を確認できません。');
    }
    final state = parse(raw['state'], actor);
    final configurations = parseConfigurations({'schema': 1, 'actor_id': actor,
      'configurations': raw['configurations']}, actor);
    final seen = <String>{};
    final planned = <ScheduledCheckoutNotification>[];
    for (final v in raw['planned_notifications'] as List) {
      if (v is! Map || v['source_id'] is! String || v['worker_id'] is! String ||
          v['work_date'] is! String || v['fire_at'] is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(v['worker_id'] as String)) {
        throw StateError('退勤通知の対象を確認できません。');
      }
      final day = DateTime.tryParse(v['work_date'] as String);
      if (day == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v['work_date'] as String) ||
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}' != v['work_date']) {
        throw StateError('退勤通知の日付を確認できません。');
      }
      final source = v['source_clock_in_id'];
      final key = source == null ? '$actor:${v['worker_id']}:${v['work_date']}' : '$actor:$source';
      if (v['source_id'] != key || !seen.add(key) ||
          (source != null && !state.targets.any((t) => t.sourceId == source && t.workerId == v['worker_id'] && t.workDate == v['work_date']))) {
        throw StateError('退勤通知の勤務対象が一致しません。');
      }
      if (source == null && !configurations.any((c) => c.workerId == v['worker_id'] && c.enabled)) {
        throw StateError('退勤通知の設定対象を確認できません。');
      }
      final fire = DateTime.tryParse(v['fire_at'] as String);
      if (fire == null || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(v['fire_at'] as String) ||
          !fire.isAfter(state.serverTime) || fire.difference(state.serverTime) >= const Duration(days: 8)) {
        throw StateError('退勤通知の予定時刻を確認できません。');
      }
      if (source != null && !state.targets.any((t) => t.sourceId == source && t.reminderAt.isAtSameMomentAs(fire))) {
        throw StateError('退勤通知の予定が勤務原本と一致しません。');
      }
      planned.add(ScheduledCheckoutNotification(sourceId: key, workerId: v['worker_id'] as String,
        workDate: v['work_date'] as String, sourceClockInId: source as String?, fireAt: fire.toUtc()));
    }
    if (!state.enabled && planned.isNotEmpty) { throw StateError('退勤通知の提供状態が一致しません。'); }
    return ScheduledCheckoutNotificationPlan(actorId: actor, configurations: configurations,
      state: state, plannedNotifications: List.unmodifiable(planned));
  }

  @visibleForTesting
  static List<GpsWorkScheduleConfiguration> parseConfigurations(Object? raw, String actor) {
    if (raw is! Map || raw['schema'] != 1 || raw['actor_id'] != actor || raw['configurations'] is! List) {
      throw StateError('出退勤時刻の設定を確認できません。');
    }
    String id(Object? v) {
      if (v is! String || !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(v)) {
        throw StateError('出退勤時刻の対象を確認できません。');
      }
      return v;
    }
    int minutes(Object? v) {
      if (v is! String || !RegExp(r'^\d{2}:\d{2}:00$').hasMatch(v)) { throw StateError('出退勤時刻を確認できません。'); }
      final parts = v.split(':').map(int.parse).toList();
      if (parts[0] > 23 || parts[1] > 59) { throw StateError('出退勤時刻を確認できません。'); }
      return parts[0] * 60 + parts[1];
    }
    final seen = <String>{};
    return List.unmodifiable((raw['configurations'] as List).map((v) {
      if (v is! Map || v['enabled'] is! bool || v['checkout_next_day'] is! bool ||
          v['revision'] is! int || (v['revision'] as int) < 1 || v['timezone'] != 'Asia/Tokyo' || v['weekdays'] is! List) {
        throw StateError('出退勤時刻の設定を確認できません。');
      }
      final days = v['weekdays'] as List;
      if (days.isEmpty || days.length > 7 || days.any((v) => v is! int || v < 1 || v > 7) || days.toSet().length != days.length) {
        throw StateError('出退勤の曜日を確認できません。');
      }
      final cin = minutes(v['clock_in_time']), cout = minutes(v['checkout_time']);
      if (cin == cout || v['checkout_next_day'] != (cout < cin)) { throw StateError('出退勤時刻の関係を確認できません。'); }
      final site = v['site_id'] == null ? null : id(v['site_id']);
      final route = v['route_assignment_id'] == null ? null : id(v['route_assignment_id']);
      if ((site == null) == (route == null)) { throw StateError('出退勤時刻の勤務先を確認できません。'); }
      final worker = id(v['worker_id']);
      if (!seen.add(worker)) { throw StateError('出退勤時刻の対象が重複しています。'); }
      return GpsWorkScheduleConfiguration(companyId: id(v['company_id']), workerId: worker,
        siteId: site, routeId: route, weekdays: List<int>.unmodifiable(days.cast<int>()),
        clockInTime: v['clock_in_time'] as String, checkoutTime: v['checkout_time'] as String,
        checkoutNextDay: v['checkout_next_day'] as bool, enabled: v['enabled'] as bool,
        revision: v['revision'] as int, timezone: 'Asia/Tokyo');
    }));
  }

  @visibleForTesting
  static ScheduledCheckoutState parse(Object? value, String actor) {
    if (value is! Map || value['schema'] != 1 || value['actor_id'] != actor ||
        value['feature_enabled'] is! bool || value['items'] is! List) {
      throw StateError('退勤予定の状態を確認できません。');
    }
    DateTime instant(Object? v) {
      if (v is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(v)) {
        throw StateError('退勤予定時刻を確認できません。');
      }
      final result = DateTime.tryParse(v);
      if (result == null) { throw StateError('退勤予定時刻を確認できません。'); }
      return result.toUtc();
    }
    String id(Object? v) {
      if (v is! String || !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(v)) {
        throw StateError('退勤対象を確認できません。');
      }
      return v;
    }
    final serverTime = instant(value['server_time']);
    final seen = <String>{};
    final targets = <ScheduledCheckoutTarget>[];
    for (final v in value['items'] as List) {
      if (v is! Map || v['due'] is! bool || v['can_manage_attendance'] is! bool ||
          v['scope_fingerprint'] is! String || (v['scope_fingerprint'] as String).isEmpty) {
        throw StateError('退勤予定の対象を確認できません。');
      }
      final day = v['work_date'];
      final parsed = day is String ? DateTime.tryParse(day) : null;
      if (parsed == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day as String) ||
          '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' != day) {
        throw StateError('退勤対象の日付を確認できません。');
      }
      final site = v['site_id'] == null ? null : id(v['site_id']);
      final route = v['route_assignment_id'] == null ? null : id(v['route_assignment_id']);
      if ((site == null) == (route == null)) { throw StateError('退勤対象の勤務先を確認できません。'); }
      final source = id(v['source_clock_in_id']);
      if (!seen.add(source)) { throw StateError('退勤対象が重複しています。'); }
      final reminder = instant(v['reminder_at']);
      if (v['due'] != !reminder.isAfter(serverTime)) {
        throw StateError('退勤予定の判定が一致しません。');
      }
      targets.add(ScheduledCheckoutTarget(companyId: id(v['company_id']),
        workerId: id(v['worker_id']), sourceId: source, workDate: day,
        siteId: site, routeId: route, reminderAt: reminder,
        due: v['due'] as bool, canManageAttendance: v['can_manage_attendance'] as bool,
        scopeFingerprint: v['scope_fingerprint'] as String));
    }
    if (value['feature_enabled'] == false && targets.isNotEmpty) {
      throw StateError('退勤確認の提供状態を確認できません。');
    }
    return ScheduledCheckoutState(actorId: actor, enabled: value['feature_enabled'] as bool,
      serverTime: serverTime, targets: List.unmodifiable(targets));
  }
}
