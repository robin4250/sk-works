import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

@immutable
class PendingCheckoutRegistration {
  const PendingCheckoutRegistration({required this.companyId, required this.workerId,
    required this.workDate, required this.sourceClockInId, required this.clockOutId,
    required this.state, required this.blocking, required this.scopeFingerprint,
    this.siteId, this.routeId, this.reportId, this.choiceAvailable = false, this.memberCount, this.reportStarted = false});
  final String companyId, workerId, sourceClockInId, clockOutId, state, scopeFingerprint;
  final DateTime workDate;
  final String? siteId, routeId, reportId;
  final bool blocking;
  final bool choiceAvailable;
  final bool reportStarted;
  final int? memberCount;
  String get identity => '$companyId/$workerId/$sourceClockInId/$clockOutId';
}

/// Only this server-scoped contract can release the global registration gate.
/// A cached signature or a Navigator result is never an unlock instruction.
class CheckoutReportGateRepository {
  CheckoutReportGateRepository(this.client);
  final SupabaseClient client;
  bool? _enforcementEnabled;
  bool? _choiceEnforcementEnabled;
  bool? get choiceEnforcementEnabled => _choiceEnforcementEnabled;
  String? _effectiveFrom;
  bool? get enforcementEnabled => _enforcementEnabled;
  String? get effectiveFrom => _effectiveFrom;
  String? get actorId => client.auth.currentUser?.id;
  static CheckoutReportGateRepository? maybeCreate() => SupabaseBackend.isInitialized
      ? CheckoutReportGateRepository(SupabaseBackend.client) : null;

  Future<List<PendingCheckoutRegistration>> readPending() async {
    final actor = actorId;
    if (actor == null) { throw StateError('ログイン状態を確認してください。'); }
    _enforcementEnabled = null;
    _choiceEnforcementEnabled = null;
    _effectiveFrom = null;
    final raw = await client.rpc('read_pending_checkout_report_registration');
    if (actorId != actor) { throw StateError('ログイン状態が変わりました。'); }
    final rows = parse(raw, actor);
    final envelope = raw as Map;
    _enforcementEnabled = envelope['enforcement_enabled'] as bool;
    _choiceEnforcementEnabled = envelope['choice_enforcement_enabled'] == true;
    _effectiveFrom = envelope['effective_from'] as String?;
    return rows;
  }

  Future<List<PendingCheckoutRegistration>> readCreationSources(DateTime month) async {
    final actor = actorId;
    if (actor == null) throw StateError('ログイン状態を確認してください。');
    final raw = await client.rpc('read_checkout_report_creation_sources', params: {
      'p_month': '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01',
    });
    if (actorId != actor) throw StateError('ログイン状態が変わりました。');
    return parse(raw, actor);
  }

  Future<bool> isOwnWorker(String workerId) async {
    final actor = actorId;
    if (actor == null) throw StateError('ログイン状態を確認してください。');
    final row = await client.from('workers').select('id').eq('id', workerId)
      .eq('user_id', actor).maybeSingle();
    if (actorId != actor) throw StateError('ログイン状態が変わりました。');
    return row != null;
  }

  Future<void> choose(PendingCheckoutRegistration target, {required bool createReport}) async {
    final actor = actorId;
    if (actor == null || !target.choiceAvailable) {
      throw StateError('日報作成の選択状態を確認してください。');
    }
    final raw = await client.rpc('choose_checkout_report_registration', params: {
      'p_source_clock_in_id': target.sourceClockInId,
      'p_expected_scope': target.scopeFingerprint,
      'p_create_report': createReport,
    });
    if (actorId != actor) { throw StateError('ログイン状態が変わりました。'); }
    parse(raw, actor);
  }

  @visibleForTesting
  static List<PendingCheckoutRegistration> parse(Object? raw, String actor) {
    if (raw is! Map || raw['schema'] != 1 || raw['actor_id'] != actor || raw['items'] is! List || raw['enforcement_enabled'] is! bool || !raw.containsKey('effective_from')) {
      throw StateError('日報の登録状態を確認できません。');
    }
    if (raw.containsKey('choice_enforcement_enabled') && raw['choice_enforcement_enabled'] is! bool) {
      throw StateError('日報作成の提供状態を確認できません。');
    }
    final effective = raw['effective_from'];
    if (raw['enforcement_enabled'] == true) {
      final date = effective is String ? DateTime.tryParse(effective) : null;
      if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(effective as String) ||
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' != effective) {
        throw StateError('日報の適用開始日を確認できません。');
      }
    } else if (effective != null || (raw['items'] as List).isNotEmpty) {
      throw StateError('日報の適用状態を確認できません。');
    }
    String id(Object? value) {
      if (value is! String || !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value)) {
        throw StateError('日報の対象を確認できません。');
      }
      return value;
    }
    final result = <PendingCheckoutRegistration>[];
    final identities = <String>{};
    for (final row in raw['items'] as List) {
      if (row is! Map || row['blocking'] is! bool || row['registration_state'] is! String ||
          row['scope_fingerprint'] is! String || (row['scope_fingerprint'] as String).isEmpty) {
        throw StateError('日報の登録状態を確認できません。');
      }
      const blockingStates = {'report_missing', 'source_conflict', 'report_input_incomplete', 'reporter_signature_missing', 'report_choice_required'};
      const nonblockingStates = {'reporter_saved_waiting_supervisor', 'signed_projection_unverified', 'completed', 'checkout_deferred'};
      if (!(row['blocking'] == true ? blockingStates : nonblockingStates).contains(row['registration_state'])) {
        throw StateError('日報の完了状態を確認できません。');
      }
      if (row['blocking'] == false && row['report_id'] == null && row['registration_state'] != 'checkout_deferred') {
        throw StateError('登録済み日報を確認できません。');
      }
      final choiceAvailable = row['choice_available'] == true;
      if (choiceAvailable && raw['choice_enforcement_enabled'] != true) {
        throw StateError('日報作成の提供状態が一致しません。');
      }
      final memberCount = row['member_count'];
      if ((row['registration_state'] == 'report_choice_required' || row['registration_state'] == 'checkout_deferred') &&
          (!choiceAvailable || memberCount is! int || memberCount < 1 ||
            (row['registration_state'] == 'report_choice_required' && memberCount < 2))) {
        throw StateError('当日の現場メンバーを確認できません。');
      }
      final dateText = row['work_date'];
      final date = dateText is String ? DateTime.tryParse(dateText) : null;
      if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateText as String) ||
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}' != dateText) {
        throw StateError('日報の対象日を確認できません。');
      }
      final site = row['site_id'] == null ? null : id(row['site_id']);
      final route = row['route_assignment_id'] == null ? null : id(row['route_assignment_id']);
      if ((site == null) == (route == null)) { throw StateError('日報の勤務先を確認できません。'); }
      final target = PendingCheckoutRegistration(companyId: id(row['company_id']),
        workerId: id(row['worker_id']), workDate: date, siteId: site, routeId: route,
        reportId: row['report_id'] == null ? null : id(row['report_id']),
        sourceClockInId: id(row['source_clock_in_id']), clockOutId: id(row['clock_out_id']),
        state: row['registration_state'] as String, blocking: row['blocking'] as bool,
        scopeFingerprint: row['scope_fingerprint'] as String,
        choiceAvailable: choiceAvailable, reportStarted: row['report_started'] == true, memberCount: memberCount is int ? memberCount : null);
      if (!identities.add(target.identity)) { throw StateError('日報の対象が重複しています。'); }
      result.add(target);
    }
    return List.unmodifiable(result);
  }
}
