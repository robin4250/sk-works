import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'checkout_report_gate.dart';
import 'attendance_management_company_allowances.dart';
import '../daily_reports/daily_report_company_allowance_selection.dart';

class AttendanceManagementOption {
  const AttendanceManagementOption({required this.id, required this.name});
  final String id;
  final String name;
}

class AttendanceManagementReport {
  const AttendanceManagementReport({required this.id, required this.companyId,
    required this.date, this.siteId, this.routeId});
  final String id, companyId;
  final DateTime date;
  final String? siteId, routeId;
}

class AttendanceManagementCell {
  const AttendanceManagementCell({
    required this.mode,
    required this.date,
    required this.workerId,
    this.siteId,
    this.manDays = 1,
    this.overtimeHours = 0,
    this.earlyHours = 0,
    this.nightHours = 0,
    this.allowanceNames = const [],
    this.notes = '',
    this.workDescription = '',
    this.clockIn,
    this.clockOut,
    this.hasUnrecordedPunches = false,
    this.reportId,
  });
  final String mode;
  final DateTime date;
  final String workerId;
  final String? siteId;
  final double manDays;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final List<String> allowanceNames;
  final String notes;
  final String workDescription;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final bool hasUnrecordedPunches;
  final String? reportId;
}

class AttendanceManagementRepository {
  AttendanceManagementRepository._(this._client);

  AttendanceManagementRepository.forTesting(this._client);
  final SupabaseClient _client;

  static AttendanceManagementRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AttendanceManagementRepository._(client);
  }

  Future<({String companyId, bool allowed})> _access() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');
    final token = _client.auth.currentSession?.accessToken;
    void current() {
      if (_client.auth.currentUser?.id != user.id ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました。読み込み直してください。');
      }
    }
    final rows = await _client.from('company_members').select('company_id,role').eq('user_id', user.id).limit(1);
    current();
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    final companyId = rows.first['company_id']?.toString() ?? '';
    final role = rows.first['role']?.toString() ?? '';
    final permissions = await _client.rpc('current_feature_permissions');
    current();
    final canManage = permissions is Map && Map<String, dynamic>.from(permissions)['can_manage_attendance'] == true;
    return (companyId: companyId, allowed: const {'owner', 'admin', 'manager'}.contains(role) && canManage);
  }

  Future<T> _registeredAllowanceRead<T>(Future<T> Function(String companyId) read) async {
    final session = _client.auth.currentSession;
    final actor = _client.auth.currentUser?.id;
    final token = session?.accessToken;
    if (actor == null || token == null || session?.isExpired != false) {
      throw StateError('ログイン状態を確認してください。');
    }
    var changed = false;
    final subscription = _client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != actor || event.session?.accessToken != token) changed = true;
    });
    try {
      final access = await _access();
      if (!access.allowed) throw StateError('勤怠管理を利用する権限がありません。');
      final result = await read(access.companyId);
      await Future<void>.delayed(Duration.zero);
      if (changed || _client.auth.currentUser?.id != actor ||
          _client.auth.currentSession?.accessToken != token || _client.auth.currentSession?.isExpired != false) {
        throw StateError('ログイン状態が変わりました。共通手当を再読み込みしてください。');
      }
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  Future<AttendanceManagementAllowanceOptions> loadCompanyAllowanceOptions(Iterable<String> workerIds) {
    final ids = workerIds.toSet().toList()..sort();
    if (ids.isEmpty || ids.any((id) => id.isEmpty)) throw StateError('従業員を選択してください。');
    return _registeredAllowanceRead((companyId) async {
      final raw = await _client.rpc('read_management_company_allowance_options',
        params: {'p_worker_ids': ids}).timeout(const Duration(seconds: 15));
      return AttendanceManagementAllowanceOptions.parse(raw, companyId: companyId, workerIds: ids);
    });
  }

  Future<AttendanceManagementSavedAllowances> loadSavedCompanyAllowances({
    required String workerId, required DateTime date, String? reportId, String? siteId,
  }) => _registeredAllowanceRead((companyId) async {
    var query = _client.from('daily_report_workers').select(
      'report_id,company_allowance_selections,company_allowance_legacy_labels,daily_reports!inner(company_id,report_date,site_id)',
    ).eq('worker_id', workerId).eq('daily_reports.company_id', companyId)
      .eq('daily_reports.report_date', _dbDate(date));
    if (reportId != null) query = query.eq('report_id', reportId);
    if (siteId != null) query = query.eq('daily_reports.site_id', siteId);
    final rows = await query.limit(2);
    if (rows.isEmpty) return const AttendanceManagementSavedAllowances();
    if (rows.length != 1) throw StateError('同日に複数の日報があります。対象の日報で共通手当を確認してください。');
    final row = rows.single;
    final raw = row['company_allowance_selections'];
    final legacy = row['company_allowance_legacy_labels'];
    if (legacy != null && legacy is! String) throw const FormatException('保存済みの手当名を確認できません。');
    return AttendanceManagementSavedAllowances(reportId: row['report_id'] as String?,
      selections: raw == null ? null : DailyReportCompanyAllowanceSelections.fromJson(raw),
      legacyLabels: legacy as String?);
  });

  /// Existing reports only: membership, company and date are all server filters.
  /// Opening this list never creates work, a report or a signature.
  Future<List<AttendanceManagementReport>> loadReports({required String workerId,
      required DateTime date}) async {
    final actor = _client.auth.currentUser?.id;
    final token = _client.auth.currentSession?.accessToken;
    void current() {
      if (actor == null || _client.auth.currentUser?.id != actor ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました。読み込み直してください。');
      }
    }
    current();
    final access = await _access();
    current();
    if (!access.allowed) throw StateError('勤怠管理を利用する権限がありません。');
    final day = _dbDate(date);
    final rows = await _client.from('daily_reports')
        .select('id,company_id,report_date,site_id,route_assignment_id,daily_report_workers!inner(worker_id)')
        .eq('company_id', access.companyId).eq('report_date', day)
        .eq('daily_report_workers.worker_id', workerId).order('id');
    current();
    final latest = await _access();
    current();
    if (!latest.allowed || latest.companyId != access.companyId) {
      throw StateError('勤怠管理の権限が変わりました。読み込み直してください。');
    }
    return List.unmodifiable(rows.map((row) {
      final members = row['daily_report_workers'];
      final site = row['site_id'] as String?;
      final route = row['route_assignment_id'] as String?;
      if (row['company_id'] != access.companyId || row['report_date'] != day ||
          row['id'] is! String || (row['id'] as String).isEmpty ||
          (site == null) == (route == null) || members is! List ||
          !members.any((member) => member is Map && member['worker_id'] == workerId)) {
        throw StateError('選択した従業員・日付の日報を確認できません。');
      }
      return AttendanceManagementReport(id: row['id'] as String,
        companyId: access.companyId, date: DateTime(date.year, date.month, date.day),
        siteId: site, routeId: route);
    }));
  }

  Future<({List<AttendanceManagementOption> workers, List<AttendanceManagementOption> sites})> loadOptions() async {
    final access = await _access();
    if (!access.allowed) throw StateError('勤怠管理を利用する権限がありません。');
    final values = await Future.wait([
      _client.from('workers').select('id,name').eq('company_id', access.companyId).eq('status', 'active').order('name'),
      _client.from('sites').select('id,name').eq('company_id', access.companyId).order('name'),
    ]);
    return (
      workers: [
        for (final raw in values[0] as List<dynamic>)
          if ((raw as Map)['id'] != null)
            AttendanceManagementOption(
              id: raw['id'].toString(),
              name: raw['name']?.toString().trim().isNotEmpty == true ? raw['name'].toString().trim() : '名前未登録',
            ),
      ],
      sites: [
        for (final raw in values[1] as List<dynamic>)
          if ((raw as Map)['id'] != null)
            AttendanceManagementOption(
              id: raw['id'].toString(),
              name: raw['name']?.toString().trim().isNotEmpty == true ? raw['name'].toString().trim() : '現場名未登録',
            ),
      ],
    );
  }

  /// Read-only: recorded work and approved leave take precedence over punches.
  /// Scope comes from a visible draft, never from an employee name or list order.
  Future<PayrollPendingAttendance?> loadPayrollPendingDays(String statementId) async {
    final userId = _client.auth.currentUser?.id;
    final token = _client.auth.currentSession?.accessToken;
    void current() {
      if (userId == null || token == null ||
          _client.auth.currentUser?.id != userId ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました。読み込み直してください。');
      }
    }
    current();
    final access = await _access();
    current();
    if (!access.allowed) return null;
    final row = await _client.from('payroll_statements')
        .select('id,company_id,worker_id,period_start,workflow_state')
        .eq('id', statementId).eq('company_id', access.companyId).maybeSingle();
    current();
    if (row == null || row['workflow_state'] != 'draft') return null;
    final workerId = row['worker_id']?.toString() ?? '';
    final period = DateTime.tryParse(row['period_start']?.toString() ?? '');
    if (workerId.isEmpty || period == null) throw StateError('給与の対象を確認できません。');
    final start = DateTime(period.year, period.month);
    final end = DateTime(period.year, period.month + 1);
    final from = _dbDate(start), until = _dbDate(end);
    final entries = await _client.from('attendance_entries').select('work_date')
        .eq('company_id', access.companyId).eq('worker_id', workerId)
        .gte('work_date', from).lt('work_date', until);
    current();
    final leaves = await _client.from('paid_leave_requests').select('leave_date')
        .eq('company_id', access.companyId).eq('worker_id', workerId)
        .eq('status', 'approved').gte('leave_date', from).lt('leave_date', until);
    current();
    final punches = await _client.from('attendance_verifications')
        .select('work_date,event_type,confirmed_at')
        .eq('company_id', access.companyId).eq('worker_id', workerId)
        .or('and(work_date.gte.$from,work_date.lt.$until),and(work_date.is.null,confirmed_at.gte.${start.toUtc().toIso8601String()},confirmed_at.lt.${end.toUtc().toIso8601String()})');
    current();
    final recorded = {
      for (final entry in entries) entry['work_date']?.toString(),
      for (final leave in leaves) leave['leave_date']?.toString(),
    };
    final days = <DateTime>{};
    for (final punch in punches) {
      if (!const {'clock_in', 'clock_out'}.contains(punch['event_type'])) continue;
      final time = DateTime.tryParse(punch['confirmed_at']?.toString() ?? '')?.toLocal();
      if (time == null) continue;
      final rawDate = punch['work_date'];
      final date = rawDate == null ? time : DateTime.tryParse(rawDate.toString());
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      if (!day.isBefore(start) && day.isBefore(end) && !recorded.contains(_dbDate(day))) days.add(day);
    }
    return PayrollPendingAttendance(workerId: workerId, dates: days.toList()..sort());
  }

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  /// Calendar evidence is read-only; punches are not completed attendance.
  Future<Map<int, Set<String>>> loadMonthMarks({required String workerId,
      required DateTime month}) async {
    final actor = _client.auth.currentUser?.id;
    final token = _client.auth.currentSession?.accessToken;
    void current() {
      if (actor == null || _client.auth.currentUser?.id != actor ||
          _client.auth.currentSession?.accessToken != token) {
        throw StateError('ログイン状態が変わりました。読み込み直してください。');
      }
    }
    current();
    final access = await _access();
    current();
    if (!access.allowed) throw StateError('勤怠管理を利用する権限がありません。');
    final from = _dbDate(DateTime(month.year, month.month));
    final until = _dbDate(DateTime(month.year, month.month + 1));
    final values = await Future.wait([
      _client.from('attendance_entries').select('work_date')
        .eq('company_id', access.companyId).eq('worker_id', workerId)
        .gte('work_date', from).lt('work_date', until),
      _client.from('paid_leave_requests').select('leave_date')
        .eq('company_id', access.companyId).eq('worker_id', workerId).eq('status', 'approved')
        .gte('leave_date', from).lt('leave_date', until),
      _client.from('attendance_verifications').select('work_date,event_type')
        .eq('company_id', access.companyId).eq('worker_id', workerId)
        .gte('work_date', from).lt('work_date', until),
    ]);
    current();
    final latest = await _access();
    current();
    if (!latest.allowed || latest.companyId != access.companyId) {
      throw StateError('勤怠管理の権限が変わりました。読み込み直してください。');
    }
    final marks = <int, Set<String>>{};
    void add(Object? value, String kind) {
      final text = value?.toString();
      final day = DateTime.tryParse(text ?? '');
      if (day == null || _dbDate(day) != text || day.year != month.year || day.month != month.month) {
        throw StateError('勤務日の記録を確認できません。');
      }
      marks.putIfAbsent(day.day, () => <String>{}).add(kind);
    }
    for (final row in values[0]) { add(row['work_date'], 'work'); }
    for (final row in values[1]) { add(row['leave_date'], 'leave'); }
    for (final row in values[2]) {
      if (const {'clock_in', 'clock_out'}.contains(row['event_type'])) {
        add(row['work_date'], 'punch');
      }
    }
    for (final kinds in marks.values) {
      if (kinds.contains('work')) kinds.remove('punch');
    }
    return Map.unmodifiable({for (final entry in marks.entries)
      entry.key: Set<String>.unmodifiable(entry.value)});
  }

  Future<AttendanceManagementCell> loadCell({required String workerId, required DateTime date}) async {
    final access = await _access();
    if (!access.allowed) throw StateError('勤怠管理を利用する権限がありません。');
    final day = _dbDate(date);
    final entries = await _client.from('attendance_entries').select(
      'id,site_id,base_man_days,overtime_hours,early_hours,night_hours,allowance_names,notes,source_report_id',
    ).eq('company_id', access.companyId).eq('worker_id', workerId).eq('work_date', day).limit(1);
    if (entries.isNotEmpty) {
      final row = Map<String, dynamic>.from(entries.first);
      final reportId = row['source_report_id']?.toString();
      var workDescription = '';
      if (reportId != null && reportId.isNotEmpty) {
        final reports = await _client.from('daily_reports').select('work_description').eq('id', reportId).limit(1);
        if (reports.isNotEmpty) workDescription = reports.first['work_description']?.toString() ?? '';
      }
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      var verificationQuery = _client.from('attendance_verifications').select('event_type,confirmed_at')
          .eq('company_id', access.companyId).eq('worker_id', workerId);
      // A report owns its entire shift, including a next-day clock-out.
      if (reportId != null && reportId.isNotEmpty) {
        verificationQuery = verificationQuery.or('daily_report_id.eq.$reportId,work_date.eq.$day');
      } else {
        verificationQuery = verificationQuery
            .or('work_date.eq.$day,and(work_date.is.null,confirmed_at.gte.${start.toUtc().toIso8601String()},confirmed_at.lt.${end.toUtc().toIso8601String()})');
      }
      final verifications = await verificationQuery.order('confirmed_at');
      DateTime? clockIn;
      DateTime? clockOut;
      for (final raw in verifications) {
        final time = DateTime.tryParse(raw['confirmed_at']?.toString() ?? '')?.toLocal();
        if (time == null) continue;
        if (raw['event_type'] == 'clock_in' && (clockIn == null || time.isBefore(clockIn))) clockIn = time;
        if (raw['event_type'] == 'clock_out' && (clockOut == null || time.isAfter(clockOut))) clockOut = time;
      }
      return AttendanceManagementCell(
        mode: 'work', date: date, workerId: workerId, reportId: reportId,
        siteId: row['site_id']?.toString(),
        manDays: _number(row['base_man_days']),
        overtimeHours: _number(row['overtime_hours']),
        earlyHours: _number(row['early_hours']),
        nightHours: _number(row['night_hours']),
        allowanceNames: [
          for (final value in (row['allowance_names'] as List<dynamic>? ?? const []))
            if (value?.toString().trim().isNotEmpty == true) value.toString().trim(),
        ],
        notes: row['notes']?.toString() ?? '',
        workDescription: workDescription,
        clockIn: clockIn, clockOut: clockOut,
      );
    }
    final leaves = await _client.from('paid_leave_requests').select('reason')
        .eq('company_id', access.companyId).eq('worker_id', workerId).eq('leave_date', day).eq('status', 'approved').limit(1);
    if (leaves.isNotEmpty) {
      return AttendanceManagementCell(mode: 'paid_leave', date: date, workerId: workerId, notes: leaves.first['reason']?.toString() ?? '');
    }
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final punches = await _client.from('attendance_verifications')
        .select('event_type,confirmed_at,site_id')
        .eq('company_id', access.companyId).eq('worker_id', workerId)
        .or('work_date.eq.$day,and(work_date.is.null,confirmed_at.gte.${start.toUtc().toIso8601String()},confirmed_at.lt.${end.toUtc().toIso8601String()})')
        .order('confirmed_at');
    DateTime? clockIn;
    DateTime? clockOut;
    final sites = <String>{};
    for (final punch in punches) {
      final time = DateTime.tryParse(punch['confirmed_at']?.toString() ?? '')?.toLocal();
      if (time == null || !const {'clock_in', 'clock_out'}.contains(punch['event_type'])) continue;
      final site = punch['site_id']?.toString();
      if (site != null && site.isNotEmpty) sites.add(site);
      if (punch['event_type'] == 'clock_in' && (clockIn == null || time.isBefore(clockIn))) clockIn = time;
      if (punch['event_type'] == 'clock_out' && (clockOut == null || time.isAfter(clockOut))) clockOut = time;
    }
    return AttendanceManagementCell(mode: clockIn != null || clockOut != null ? 'pending_work' : 'off', date: date, workerId: workerId,
      manDays: 0, siteId: sites.length == 1 ? sites.single : null,
      clockIn: clockIn, clockOut: clockOut,
      hasUnrecordedPunches: clockIn != null || clockOut != null);

  }

  Future<int> apply({
    required String action,
    required Iterable<String> workerIds,
    required Iterable<DateTime> dates,
    required String mode,
    String? siteId,
    double manDays = 1,
    double overtimeHours = 0,
    double earlyHours = 0,
    double nightHours = 0,
    List<String> allowanceNames = const [],
    DailyReportCompanyAllowanceSelections? companyAllowanceSelections,
    String? companyAllowanceLegacyLabels,
    String notes = '',
    String workDescription = '',
    String? clockIn,
    String? clockOut,
  }) async {
    final workers = workerIds.toSet().where((id) => id.isNotEmpty).toList();
    final selectedDates = dates.map((date) => DateTime(date.year, date.month, date.day)).toSet().toList()..sort();
    if (workers.isEmpty || selectedDates.isEmpty) throw StateError('従業員と日付を選択してください。');
    final items = <Map<String, dynamic>>[
      for (final workerId in workers)
        for (final date in selectedDates)
          {
            'worker_id': workerId,
            'date': _dbDate(date),
            'mode': mode,
            'site_id': siteId,
            'man_days': manDays,
            'overtime_hours': overtimeHours,
            'early_hours': earlyHours,
            'night_hours': nightHours,
            'allowance_names': allowanceNames,
            if (companyAllowanceSelections != null) 'company_allowance_selections': companyAllowanceSelections.toJson(),
            if (companyAllowanceLegacyLabels != null) 'company_allowance_legacy_labels': companyAllowanceLegacyLabels,
            'notes': notes.trim(),
            'work_description': workDescription.trim(),
            'clock_in': clockIn,
            'clock_out': clockOut,
          },
    ];
    final actor = _client.auth.currentUser?.id;
    final raw = await _client.rpc('force_manage_attendance', params: {'p_action': action, 'p_items': items});
    final gate = CheckoutReportGateController.instance;
    // The server decides whether the affected worker is this actor and has a
    // new obligation. A proxy write is never itself a reporter obligation.
    if (actor != null && _client.auth.currentUser?.id == actor && gate.actorId == actor) {
      gate.requestCheck();
    }
    return (raw as num?)?.toInt() ?? items.length;
  }

  static double _number(Object? value) => (value as num?)?.toDouble() ?? double.tryParse(value?.toString() ?? '') ?? 0;
  static String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class PayrollPendingAttendance {
  const PayrollPendingAttendance({required this.workerId, required this.dates});
  final String workerId;
  final List<DateTime> dates;
}

