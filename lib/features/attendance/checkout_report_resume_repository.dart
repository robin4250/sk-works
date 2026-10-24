import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

enum CheckoutReportState {
  missing, draft, partialSignature, complete, signedWithoutAttendance,
  protectedPeriod, conflict,
}

@immutable
class CheckoutReportResumeTarget {
  const CheckoutReportResumeTarget({
    required this.companyId, required this.workerId, required this.workDate,
    required this.sourceClockInIds, required this.clockOutIds,
    required this.sourceClockInId, required this.clockOutId,
    required this.state, this.siteId, this.routeId, this.reportId,
    this.destinationName = '勤務先',
    this.reporterSignatureSaved = false,
    this.responsibleSignatureSaved = false,
  });
  final String companyId, workerId, sourceClockInId, clockOutId;
  final DateTime workDate;
  final List<String> sourceClockInIds, clockOutIds;
  final String? siteId, routeId, reportId;
  final String destinationName;
  final CheckoutReportState state;
  /// Persisted signature evidence only, not an all-required-fields gate proof.
  final bool reporterSignatureSaved, responsibleSignatureSaved;
  bool get needsCompletion => const [
    CheckoutReportState.missing, CheckoutReportState.draft,
    CheckoutReportState.partialSignature,
  ].contains(state);
  bool get complete => state == CheckoutReportState.complete;
}

/// Reads only saved evidence. Normal report saving/signing remains owned by
/// DailyReportPage and its existing scoped server RPCs.
class CheckoutReportResumeRepository {
  CheckoutReportResumeRepository(SupabaseClient client)
      : _client = client, _actor = (() => client.auth.currentUser?.id);
  @visibleForTesting
  CheckoutReportResumeRepository.forTesting(this._client, this._actor);
  final SupabaseClient _client;
  final String? Function() _actor;
  static CheckoutReportResumeRepository? maybeCreate() =>
      !SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null
          ? null : CheckoutReportResumeRepository(SupabaseBackend.client);

  void _check(String actor) {
    if (_actor() != actor) { throw StateError('ログイン状態が変わりました。画面を開き直してください。'); }
  }

  String _id(Object? value) {
    if (value is! String || !RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value)) {
      throw StateError('勤務記録のIDを確認できません。');
    }
    return value;
  }

  String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  bool _hasSignature(Object? raw, Object? name) => name is String && name.trim().isNotEmpty &&
      raw is Map && raw['strokes'] is List &&
      (raw['strokes'] as List).any((stroke) => stroke is List && stroke.isNotEmpty);

  Future<String> _company(String worker, String actor) async {
    _id(worker); _check(actor);
    final w = await _client.from('workers').select('id,company_id,user_id')
        .eq('id', worker).maybeSingle();
    _check(actor);
    if (w == null || w['id'] != worker) { throw StateError('社員の所属を確認できません。'); }
    final company = _id(w['company_id']);
    final membership = await _client.from('company_members').select('company_id,user_id,role')
        .eq('company_id', company).eq('user_id', actor).maybeSingle();
    _check(actor);
    if (membership == null || membership['company_id'] != company || membership['user_id'] != actor) {
      throw StateError('この会社の日報を確認する権限がありません。');
    }
    if (w['user_id'] != actor && !const ['owner', 'admin'].contains(membership['role'])) {
      // Use the requested company, not the first membership chosen by the
      // global current_feature_permissions RPC.
      final permission = await _client.from('member_feature_permissions')
          .select('company_id,user_id,can_manage_attendance')
          .eq('company_id', company).eq('user_id', actor).maybeSingle();
      _check(actor);
      final allowed = permission == null
          ? membership['role'] == 'manager'
          : permission['company_id'] == company && permission['user_id'] == actor &&
              permission['can_manage_attendance'] == true;
      if (!allowed) { throw StateError('この社員の日報を操作する権限がありません。'); }
    }
    return company;
  }

  Future<List<CheckoutReportResumeTarget>> loadDay({
    required String workerId, required DateTime workDate,
  }) async {
    final actor = _actor();
    if (actor == null) { throw StateError('ログインが必要です。'); }
    final company = await _company(workerId, actor);
    final day = _date(workDate);
    final rows = await _client.from('attendance_verifications')
        .select('id,company_id,worker_id,event_type,confirmed_at,work_date,source_clock_in_id,site_id,route_assignment_id,daily_report_id,sites(name),route_assignments(route_name)')
        .eq('company_id', company).eq('worker_id', workerId).eq('work_date', day)
        .order('confirmed_at').limit(401);
    _check(actor);
    if (rows.length > 400) { throw StateError('勤務記録が多いため、管理者が対象を確認してください。'); }
    final starts = <String, Map<String, dynamic>>{};
    final ends = <String, Map<String, dynamic>>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final id = _id(row['id']);
      if (row['company_id'] != company || row['worker_id'] != workerId || row['work_date'] != day ||
          DateTime.tryParse(row['confirmed_at']?.toString() ?? '') == null) {
        throw StateError('勤務日または対象社員が一致しません。');
      }
      if (row['event_type'] == 'clock_in') {
        if (starts.containsKey(id) || row['source_clock_in_id'] != null) { throw StateError('勤務開始の記録が重複しています。'); }
        starts[id] = row;
      } else if (row['event_type'] == 'clock_out') {
        final source = _id(row['source_clock_in_id']);
        if (ends.containsKey(source)) { throw StateError('退勤の記録が重複しています。'); }
        ends[source] = row;
      } else {
        throw StateError('勤務記録の種類を確認できません。');
      }
    }
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final entry in ends.entries) {
      final start = starts[entry.key], end = entry.value;
      if (start == null || start['site_id'] != end['site_id'] ||
          start['route_assignment_id'] != end['route_assignment_id'] ||
          DateTime.parse(end['confirmed_at'] as String).isBefore(DateTime.parse(start['confirmed_at'] as String))) {
        throw StateError('退勤と開始原本の対応を確認できません。');
      }
      final site = start['site_id'], route = start['route_assignment_id'];
      if ((site == null) == (route == null)) { throw StateError('勤務先の原本を確認できません。'); }
      _id(site ?? route);
      final key = '$site/$route';
      grouped.putIfAbsent(key, () => []).add({'start': start, 'end': end});
    }
    final result = <CheckoutReportResumeTarget>[];
    for (final pairs in grouped.values) {
      final first = pairs.first;
      final start = first['start'] as Map<String, dynamic>, end = first['end'] as Map<String, dynamic>;
      final site = start['site_id'] as String?, route = start['route_assignment_id'] as String?;
      var reportQuery = _client.from('daily_reports')
          .select('id,company_id,report_date,site_id,route_assignment_id,status,representative_signer_name,supervisor_signer_name,representative_signature_json,supervisor_signature_json')
          .eq('company_id', company).eq('report_date', day);
      reportQuery = site == null ? reportQuery.isFilter('site_id', null) : reportQuery.eq('site_id', site);
      reportQuery = route == null ? reportQuery.isFilter('route_assignment_id', null) : reportQuery.eq('route_assignment_id', route);
      final reports = await reportQuery.limit(2);
      _check(actor);
      if (reports.length > 1) { throw StateError('同じ勤務先の日報が重複しています。管理者が確認してください。'); }
      final report = reports.isEmpty ? null : reports.single;
      final reportId = report == null ? null : _id(report['id']);
      final reporterSaved = report != null && _hasSignature(report['representative_signature_json'], report['representative_signer_name']);
      final responsibleSaved = report != null && _hasSignature(report['supervisor_signature_json'], report['supervisor_signer_name']);
      if (report != null && (report['company_id'] != company || report['report_date'] != day ||
          report['site_id'] != site || report['route_assignment_id'] != route)) {
        throw StateError('日報の勤務先または勤務日が一致しません。');
      }
      for (final pair in pairs) {
        for (final event in [pair['start'] as Map, pair['end'] as Map]) {
          if (event['daily_report_id'] != null && event['daily_report_id'] != reportId) {
            throw StateError('勤務証跡と保存済み日報が一致しません。管理者が確認してください。');
          }
        }
      }
      var formalQuery = _client.from('attendance_entries')
          .select('id,company_id,worker_id,work_date,site_id,route_assignment_id,source_report_id,base_man_days')
          .eq('company_id', company).eq('worker_id', workerId).eq('work_date', day);
      formalQuery = site == null ? formalQuery.isFilter('site_id', null) : formalQuery.eq('site_id', site);
      formalQuery = route == null ? formalQuery.isFilter('route_assignment_id', null) : formalQuery.eq('route_assignment_id', route);
      final formal = await formalQuery.limit(2);
      _check(actor);
      var state = CheckoutReportState.missing;
      if (formal.length > 1 || formal.any((row) => row['company_id'] != company || row['worker_id'] != workerId ||
          row['work_date'] != day || row['site_id'] != site || row['route_assignment_id'] != route)) {
        state = CheckoutReportState.conflict;
      } else if (report != null) {
        final roster = await _client.from('daily_report_workers').select('report_id,worker_id')
            .eq('report_id', reportId!).eq('worker_id', workerId).limit(2);
        _check(actor);
        if (roster.length != 1 || roster.single['report_id'] != reportId || roster.single['worker_id'] != workerId) {
          state = CheckoutReportState.conflict;
        } else if (report['status'] == 'signed') {
          state = reporterSaved && responsibleSaved &&
              formal.length == 1 && formal.single['source_report_id'] == reportId &&
              formal.single['base_man_days'] is num && (formal.single['base_man_days'] as num) > 0
              ? CheckoutReportState.complete : CheckoutReportState.signedWithoutAttendance;
        } else if (report['status'] != 'draft') {
          state = CheckoutReportState.conflict;
        } else {
          state = report['representative_signature_json'] != null || report['supervisor_signature_json'] != null
              ? CheckoutReportState.partialSignature : CheckoutReportState.draft;
        }
      } else if (formal.isNotEmpty) {
        state = CheckoutReportState.conflict;
      }
      if (state != CheckoutReportState.complete) {
        final month = '${day.substring(0, 7)}-01';
        final payroll = await _client.from('payroll_statements')
            .select('company_id,worker_id,period_start,workflow_state,automatic_calculation,finalized_at')
            .eq('company_id', company).eq('worker_id', workerId).eq('period_start', month).limit(2);
        _check(actor);
        if (payroll.length > 1 || payroll.any((p) => p['company_id'] != company || p['worker_id'] != workerId || p['period_start'] != month)) {
          state = CheckoutReportState.conflict;
        } else if (payroll.isNotEmpty && (payroll.single['workflow_state'] != 'draft' ||
            payroll.single['automatic_calculation'] != true || payroll.single['finalized_at'] != null)) {
          state = CheckoutReportState.protectedPeriod;
        }
      }
      final sourceIds = [for (final pair in pairs) _id((pair['start'] as Map)['id'])];
      final outIds = [for (final pair in pairs) _id((pair['end'] as Map)['id'])];
      final destination = site != null ? start['sites'] : start['route_assignments'];
      result.add(CheckoutReportResumeTarget(companyId: company, workerId: workerId,
        workDate: DateTime(workDate.year, workDate.month, workDate.day),
        sourceClockInIds: List.unmodifiable(sourceIds), clockOutIds: List.unmodifiable(outIds),
        sourceClockInId: _id(start['id']), clockOutId: _id(end['id']),
        state: state, siteId: site, routeId: route, reportId: reportId,
        reporterSignatureSaved: reporterSaved && state != CheckoutReportState.conflict,
        responsibleSignatureSaved: responsibleSaved && state != CheckoutReportState.conflict,
        destinationName: destination is Map
            ? (destination[site != null ? 'name' : 'route_name']?.toString() ?? '勤務先') : '勤務先'));
    }
    _check(actor);
    return List.unmodifiable(result);
  }

  Future<CheckoutReportResumeTarget> revalidate(CheckoutReportResumeTarget target) async {
    final rows = await loadDay(workerId: target.workerId, workDate: target.workDate);
    final matches = rows.where((row) => row.companyId == target.companyId &&
        row.siteId == target.siteId && row.routeId == target.routeId &&
        row.sourceClockInIds.contains(target.sourceClockInId) &&
        row.clockOutIds[row.sourceClockInIds.indexOf(target.sourceClockInId)] == target.clockOutId).toList();
    if (matches.length != 1) { throw StateError('退勤の原本が変わりました。再読み込みしてください。'); }
    return matches.single;
  }

  Future<CheckoutReportResumeTarget> inspectSavedCheckout(Map<String, dynamic> saved) async {
    final worker = _id(saved['worker_id']), company = _id(saved['company_id']);
    final source = _id(saved['source_clock_in_id']), end = _id(saved['id']);
    final text = saved['work_date'];
    if (text is! String || !RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(text)) { throw StateError('退勤の勤務日を確認できません。'); }
    final date = DateTime.tryParse(text);
    if (date == null || _date(date) != text) { throw StateError('退勤の勤務日を確認できません。'); }
    final rows = await loadDay(workerId: worker, workDate: date);
    final found = rows.where((row) => row.companyId == company &&
        row.sourceClockInIds.contains(source) &&
        row.clockOutIds[row.sourceClockInIds.indexOf(source)] == end &&
        row.siteId == saved['site_id'] && row.routeId == saved['route_assignment_id']).toList();
    if (found.length != 1) { throw StateError('保存した退勤の原本を確認できません。'); }
    return found.single;
  }
}
