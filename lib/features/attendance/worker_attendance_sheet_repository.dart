import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../../international/language_controller.dart';
import 'attendance_work_date.dart';
import '../daily_reports/daily_report_company_allowance_selection.dart';
import 'worker_attendance_registered_allowances.dart';
import 'attendance_pending_report_details.dart';

class PartnerAttendanceWorker {
  const PartnerAttendanceWorker({
    required this.id,
    required this.name,
    required this.companyId,
    required this.partnerId,
    required this.partnerName,
    required this.actorSession,
  });
  final String id, name, companyId, partnerId, partnerName, actorSession;
}

class AttendanceWorker {
  const AttendanceWorker({required this.id, required this.name});

  final String id;
  final String name;
}

class WorkerAttendanceDay {
  const WorkerAttendanceDay({
    required this.date,
    this.siteName,
    this.routeNames = const <String>[],
    this.clockIn,
    this.clockOut,
    this.overtimeHours = 0,
    this.earlyHours = 0,
    this.nightHours = 0,
    this.manDays = 0,
    this.hasHolidayWork = false,
    this.allowanceYen = 0,
    this.allowanceNames = const <String>[],
    this.companyAllowanceSelections =
        const <DailyReportCompanyAllowanceSelection>[],
    this.allowanceUnits = const <String, String>{},
    this.pendingReports = const <AttendancePendingReportDetails>[],
    this.paidLeave = false,
    this.paidLeaveOrdinal = 0,
    this.paidLeaveRemaining = 0,
  });

  final DateTime date;
  final String? siteName;
  final List<String> routeNames;
  String get destinationLabel =>
      routeNames.isEmpty ? siteName ?? '' : routeNames.join('／');
  final DateTime? clockIn;
  final DateTime? clockOut;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final double manDays;
  final bool hasHolidayWork;
  final int allowanceYen;
  final List<String> allowanceNames;
  final List<DailyReportCompanyAllowanceSelection> companyAllowanceSelections;

  String allowanceDisplayText(String name) =>
      companyAllowanceSelections.any((item) => item.nameSnapshot == name)
      ? name
      : '${name}1${allowanceUnits[name] ?? "回"}';
  final Map<String, String> allowanceUnits;
  final List<AttendancePendingReportDetails> pendingReports;
  final bool paidLeave;
  final int paidLeaveOrdinal;
  final double paidLeaveRemaining;

  bool get hasAllowance => allowanceNames.isNotEmpty || allowanceYen > 0;

  bool get worked => attendanceDayHasWorkedData(
    manDays: manDays,
    overtimeHours: overtimeHours,
    earlyHours: earlyHours,
    nightHours: nightHours,
    siteName: siteName,
    clockIn: clockIn,
    clockOut: clockOut,
  );
}

class WorkerAttendanceMonth {
  const WorkerAttendanceMonth({
    required this.year,
    required this.month,
    required this.days,
    this.allowanceUnits = const <String, String>{},
    this.pendingDetailsUnavailable = false,
  });

  final bool pendingDetailsUnavailable;
  final int year;
  final int month;
  final Map<DateTime, WorkerAttendanceDay> days;
  final Map<String, String> allowanceUnits;

  int get workedDays => days.values.where((day) => day.worked).length;

  /// Calendar days and billable man-days are intentionally separate units.
  double get manDays => days.values.fold(0, (sum, day) => sum + day.manDays);
  int get holidayWorkedDays =>
      days.values.where((day) => day.hasHolidayWork && day.worked).length;

  int get paidLeaveDays => days.values.where((day) => day.paidLeave).length;

  double get overtimeHours =>
      days.values.fold(0, (sum, day) => sum + day.overtimeHours);

  double get earlyHours =>
      days.values.fold(0, (sum, day) => sum + day.earlyHours);

  double get nightHours =>
      days.values.fold(0, (sum, day) => sum + day.nightHours);

  int get allowanceYen =>
      days.values.fold(0, (sum, day) => sum + day.allowanceYen);

  Map<String, int> get allowanceCounts {
    final counts = <String, int>{};
    for (final day in days.values) {
      final names = day.allowanceNames.isEmpty && day.allowanceYen > 0
          ? const <String>['手当']
          : day.allowanceNames;
      for (final raw in names) {
        final name = raw.trim();
        if (name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    return counts;
  }
}

class WorkerAttendanceSheetRepository {
  WorkerAttendanceSheetRepository._(this._client);

  /// Allows a scoped Supabase client to be supplied by read-path tests.
  WorkerAttendanceSheetRepository.forClient(this._client);

  final SupabaseClient _client;

  static WorkerAttendanceSheetRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return WorkerAttendanceSheetRepository._(client);
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return rows.first['company_id'] as String;
  }

  Stream<AuthState> get partnerAuthChanges => _client.auth.onAuthStateChange;
  bool partnerWorkerIsCurrent(PartnerAttendanceWorker worker) {
    try {
      return _partnerActorSession() == worker.actorSession;
    } catch (_) {
      return false;
    }
  }

  String _partnerText(String ja, String en) =>
      SkoLanguageController.isEnglish ? en : ja;

  String _partnerActorSession() {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError(
        _partnerText('ログイン状態を確認してください。', 'Please check your sign-in session.'),
      );
    }
    final parts = session.accessToken.split('.');
    if (parts.length != 3) {
      throw StateError(
        _partnerText('ログイン状態を確認してください。', 'Please check your sign-in session.'),
      );
    }
    final claims = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (claims is! Map ||
        claims['sub'] != session.user.id ||
        claims['session_id'] is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(claims['session_id'] as String)) {
      throw StateError(
        _partnerText('ログイン状態を確認してください。', 'Please check your sign-in session.'),
      );
    }
    return '${session.user.id}/${claims['session_id']}';
  }

  Future<String> _partnerCompany(String actorSession, String bearer) async {
    if (_partnerActorSession() != actorSession) {
      throw StateError(
        _partnerText('ログイン状態が変わりました。', 'Your sign-in session has changed.'),
      );
    }
    final actor = _client.auth.currentUser!.id;
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', actor)
        .limit(2)
        .setHeader('Authorization', 'Bearer $bearer');
    if (_partnerActorSession() != actorSession ||
        rows.length != 1 ||
        rows.single['company_id'] is! String) {
      throw StateError(
        _partnerText(
          '協力会社の出勤表を開く会社を一意に確認できません。',
          'The company for partner attendance cannot be uniquely confirmed.',
        ),
      );
    }
    return rows.single['company_id'] as String;
  }

  Future<T> _withPartnerSession<T>(
    Future<T> Function(String, String) action,
  ) async {
    final key = _partnerActorSession();
    final bearer = _client.auth.currentSession!.accessToken;
    final claims =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(bearer.split('.')[1])),
              ),
            )
            as Map;
    final expiry = claims['exp'];
    if (expiry is! int ||
        DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry) {
      throw StateError(
        _partnerText('ログイン状態を確認してください。', 'Please check your sign-in session.'),
      );
    }
    var invalidated = false;
    final subscription = partnerAuthChanges.listen((_) {
      try {
        if (_partnerActorSession() != key) invalidated = true;
      } catch (_) {
        invalidated = true;
      }
    });
    try {
      final result = await action(key, bearer);
      if (invalidated ||
          _partnerActorSession() != key ||
          DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiry) {
        throw StateError(
          _partnerText('ログイン状態が変わりました。', 'Your sign-in session has changed.'),
        );
      }
      return result;
    } finally {
      await subscription.cancel();
    }
  }

  Future<List<PartnerAttendanceWorker>>
  loadPartnerWorkers() => _withPartnerSession((session, bearer) async {
    final company = await _partnerCompany(session, bearer);
    final rows = await _client
        .from('workers')
        .select(
          'id,name,company_id,affiliation,status,partner_company_id,partner_companies(id,name,company_id)',
        )
        .eq('company_id', company)
        .eq('affiliation', 'partner_company')
        .order('name')
        .setHeader('Authorization', 'Bearer $bearer');
    if (await _partnerCompany(session, bearer) != company) {
      throw StateError(
        _partnerText('会社が変わりました。', 'The company context has changed.'),
      );
    }
    final result = <PartnerAttendanceWorker>[];
    for (final row in rows) {
      if (row['status'] == 'inactive') continue;
      final partner = row['partner_companies'];
      if (row['status'] != 'active' ||
          row['company_id'] != company ||
          row['affiliation'] != 'partner_company' ||
          row['id'] is! String ||
          row['partner_company_id'] is! String ||
          partner is! Map ||
          partner['id'] != row['partner_company_id'] ||
          partner['company_id'] != company ||
          partner['name'] is! String ||
          (partner['name'] as String).trim().isEmpty ||
          row['name'] is! String ||
          (row['name'] as String).trim().isEmpty) {
        throw StateError(
          _partnerText(
            '協力会社と作業者の対応を確認できません。',
            'The partner company and worker mapping could not be confirmed.',
          ),
        );
      }
      result.add(
        PartnerAttendanceWorker(
          id: row['id'] as String,
          name: row['name'] as String,
          companyId: company,
          partnerId: row['partner_company_id'] as String,
          partnerName: partner['name'] as String,
          actorSession: session,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  Future<List<Map<String, dynamic>>> loadPartnerAttendanceMonth(
    PartnerAttendanceWorker worker,
    DateTime month,
  ) => _withPartnerSession((session, bearer) async {
    if (session != worker.actorSession) {
      throw StateError(
        _partnerText('ログイン状態が変わりました。', 'Your sign-in session has changed.'),
      );
    }
    final company = await _partnerCompany(worker.actorSession, bearer);
    if (company != worker.companyId) {
      throw StateError(
        _partnerText('表示する会社が変わりました。', 'The company being viewed has changed.'),
      );
    }
    final workers = await _client
        .from('workers')
        .select('id,company_id,partner_company_id,affiliation,status')
        .eq('id', worker.id)
        .eq('company_id', company)
        .eq('partner_company_id', worker.partnerId)
        .setHeader('Authorization', 'Bearer $bearer');
    if (workers.length != 1 ||
        workers.single['id'] != worker.id ||
        workers.single['company_id'] != company ||
        workers.single['partner_company_id'] != worker.partnerId ||
        workers.single['affiliation'] != 'partner_company' ||
        workers.single['status'] != 'active') {
      throw StateError(
        _partnerText(
          '協力会社作業者の所属が変わりました。',
          'The partner worker affiliation has changed.',
        ),
      );
    }
    final rows = await _client
        .from('attendance_entries')
        .select(
          'id,company_id,worker_id,site_id,route_assignment_id,work_date,source_report_id,base_man_days,overtime_hours,early_hours,night_hours,sites(id,name,company_id)',
        )
        .eq('company_id', company)
        .eq('worker_id', worker.id)
        .gte('work_date', _dbDate(DateTime(month.year, month.month)))
        .lt('work_date', _dbDate(DateTime(month.year, month.month + 1)))
        .order('work_date')
        .setHeader('Authorization', 'Bearer $bearer');
    if (await _partnerCompany(worker.actorSession, bearer) != company) {
      throw StateError(
        _partnerText('会社が変わりました。', 'The company context has changed.'),
      );
    }
    final seen = <String>{};
    for (final row in rows) {
      final site = row['sites'];
      final day = row['work_date'] is String
          ? DateTime.tryParse(row['work_date'] as String)
          : null;
      final destinationValid = row['site_id'] is String
          ? row['route_assignment_id'] == null &&
                site is Map &&
                site['id'] == row['site_id'] &&
                site['company_id'] == company
          : row['site_id'] == null &&
                row['route_assignment_id'] is String &&
                site == null;
      if (row['id'] is! String ||
          !seen.add(row['id'] as String) ||
          row['company_id'] != company ||
          row['worker_id'] != worker.id ||
          !destinationValid ||
          day == null ||
          day.year != month.year ||
          day.month != month.month ||
          !RegExp(
            r'^\d{4}-\d{2}-\d{2}$',
          ).hasMatch(row['work_date'] as String) ||
          _dbDate(day) != row['work_date'] ||
          ![
            'base_man_days',
            'overtime_hours',
            'early_hours',
            'night_hours',
          ].every(
            (key) =>
                row[key] is num &&
                (row[key] as num).isFinite &&
                (row[key] as num) >= 0,
          )) {
        throw StateError(
          _partnerText(
            '協力会社の出勤記録を確認できません。',
            'Partner attendance records could not be verified.',
          ),
        );
      }
    }
    final currentWorkers = await _client
        .from('workers')
        .select('id,company_id,partner_company_id,affiliation,status')
        .eq('id', worker.id)
        .eq('company_id', company)
        .eq('partner_company_id', worker.partnerId)
        .setHeader('Authorization', 'Bearer $bearer');
    if (currentWorkers.length != 1 ||
        currentWorkers.single['id'] != worker.id ||
        currentWorkers.single['company_id'] != company ||
        currentWorkers.single['partner_company_id'] != worker.partnerId ||
        currentWorkers.single['affiliation'] != 'partner_company' ||
        currentWorkers.single['status'] != 'active' ||
        await _partnerCompany(worker.actorSession, bearer) != company) {
      throw StateError(
        _partnerText(
          '協力会社作業者の所属が変わりました。',
          'The partner worker affiliation has changed.',
        ),
      );
    }
    // Original IDs/rows only. NULL source_report is not interpreted as receipt provenance.
    return List.unmodifiable(
      rows.map((row) => Map<String, dynamic>.unmodifiable(row)),
    );
  });

  Future<List<AttendanceWorker>> loadCompanyWorkers() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('workers')
        .select('id,name,affiliation,status')
        .eq('company_id', companyId)
        .eq('affiliation', 'employee')
        .order('name');

    return [
      for (final raw in rows)
        if ((raw['id']?.toString() ?? '').isNotEmpty &&
            raw['status']?.toString() != 'inactive')
          AttendanceWorker(
            id: raw['id'].toString(),
            name: raw['name']?.toString().trim().isNotEmpty == true
                ? raw['name'].toString().trim()
                : '名前未登録',
          ),
    ];
  }

  Future<String> ensureCurrentWorkerId() async {
    final value = await _client.rpc('ensure_current_user_worker');
    final id = value?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('本人の作業員情報を確認できません。');
    }
    return id;
  }

  Future<({String reportId, String? siteId, String? routeAssignmentId})?>
  findDailyReportForDate(DateTime date, {String? workerId}) async {
    final targetWorkerId = workerId ?? await ensureCurrentWorkerId();
    final rows = await _client
        .from('daily_report_workers')
        .select(
          'report_id,daily_reports!inner(site_id,route_assignment_id,report_date)',
        )
        .eq('worker_id', targetWorkerId)
        .eq('daily_reports.report_date', _dbDate(date))
        .limit(1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    final report = row['daily_reports'];
    if (report is! Map) return null;
    final reportId = row['report_id']?.toString() ?? '';
    final siteId = report['site_id']?.toString();
    final routeAssignmentId = report['route_assignment_id']?.toString();
    if (reportId.isEmpty ||
        ((siteId == null || siteId.isEmpty) &&
            (routeAssignmentId == null || routeAssignmentId.isEmpty))) {
      return null;
    }
    return (
      reportId: reportId,
      siteId: siteId?.isEmpty == true ? null : siteId,
      routeAssignmentId: routeAssignmentId?.isEmpty == true
          ? null
          : routeAssignmentId,
    );
  }

  Future<WorkerAttendanceMonth> loadMonth(
    DateTime month, {
    String? workerId,
  }) async {
    final targetWorkerId = workerId ?? await ensureCurrentWorkerId();
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final startText = _dbDate(start);
    final endText = _dbDate(end);

    final attendanceRows = await _client
        .from('attendance_entries')
        .select(
          'id, source_report_id, work_date, site_id, base_man_days, work_category, overtime_hours, early_hours, night_hours, allowance_amount, allowance_names, sites(name)',
        )
        .eq('worker_id', targetWorkerId)
        .gte('work_date', startText)
        .lt('work_date', endText)
        .order('work_date');

    final reportIds = <String>{
      for (final row in attendanceRows)
        if (row['source_report_id'] is String)
          row['source_report_id'] as String,
    };
    final registered = reportIds.isEmpty
        ? <String, List<DailyReportCompanyAllowanceSelection>>{}
        : workerAttendanceRegisteredAllowances(
            await _client
                .from('daily_report_workers')
                .select(
                  'report_id,worker_id,company_allowance_selections,daily_reports!inner(status)',
                )
                .eq('worker_id', targetWorkerId)
                .eq('daily_reports.status', 'signed')
                .inFilter('report_id', reportIds.toList()),
            reportIds: reportIds,
            workerId: targetWorkerId,
          );

    var pendingReports = const <AttendancePendingReportDetails>[];
    var pendingDetailsUnavailable = false;
    try {
      pendingReports = AttendancePendingReportDetails.parse(
        await _client
            .from('daily_report_workers')
            .select(
              'report_id,worker_id,overtime_hours,early_hours,night_hours,allowance_label,company_allowance_selections,daily_reports!inner(id,report_date,status,sites(name))',
            )
            .eq('worker_id', targetWorkerId)
            .eq('daily_reports.status', 'draft')
            .gte('daily_reports.report_date', startText)
            .lt('daily_reports.report_date', endText),
        workerId: targetWorkerId,
        month: start,
      );
    } catch (_) {
      // This supplemental read must not hide verified attendance. Never claim
      // that missing/denied/malformed draft details are an empty confirmed set.
      pendingDetailsUnavailable = true;
    }

    final verificationRows = await _client
        .from('attendance_verifications')
        .select(
          'event_type, confirmed_at, work_date, site_id, sites(name), route_assignment_id, route_assignments(route_name), daily_reports(report_date)',
        )
        .eq('worker_id', targetWorkerId)
        .or(
          'and(work_date.gte.$startText,work_date.lt.$endText),and(work_date.is.null,confirmed_at.gte.${start.toUtc().toIso8601String()},confirmed_at.lt.${end.add(const Duration(days: 1)).toUtc().toIso8601String()})',
        )
        .order('confirmed_at');

    final drafts = <DateTime, _DayDraft>{};

    for (final raw in attendanceRows) {
      final row = Map<String, dynamic>.from(raw);
      final date = _parseDate(row['work_date']?.toString());
      if (date == null) continue;
      final key = _dateOnly(date);
      final draft = drafts.putIfAbsent(key, () => _DayDraft(key));

      final site = row['sites'];
      if (site is Map &&
          (site['name']?.toString().trim().isNotEmpty ?? false)) {
        draft.siteName ??= site['name'].toString();
      }
      final manDays = _number(row['base_man_days']);
      draft.manDays += manDays;
      if (manDays > 0 &&
          const ['holiday', 'holiday_night'].contains(row['work_category'])) {
        draft.hasHolidayWork = true;
      }
      draft.overtimeHours += _number(row['overtime_hours']);
      draft.earlyHours += _number(row['early_hours']);
      draft.nightHours += _number(row['night_hours']);
      draft.allowanceYen += (row['allowance_amount'] as num?)?.toInt() ?? 0;
      for (final selected
          in registered[row['source_report_id']] ??
              const <DailyReportCompanyAllowanceSelection>[]) {
        if (!draft.companyAllowanceSelections.any(
          (item) =>
              item.key == selected.key &&
              item.registrationVersion == selected.registrationVersion &&
              item.generation == selected.generation &&
              item.nameSnapshot == selected.nameSnapshot,
        )) {
          draft.companyAllowanceSelections.add(selected);
        }
        if (!draft.allowanceNames.contains(selected.nameSnapshot)) {
          draft.allowanceNames.add(selected.nameSnapshot);
        }
      }
      final allowanceNames = row['allowance_names'];
      if (allowanceNames is List) {
        for (final value in allowanceNames) {
          final name = value?.toString().trim() ?? '';
          if (name.isNotEmpty && !draft.allowanceNames.contains(name)) {
            draft.allowanceNames.add(name);
          }
        }
      }
    }

    for (final report in pendingReports) {
      final draft = drafts.putIfAbsent(
        report.date,
        () => _DayDraft(report.date),
      );
      draft.pendingReports.add(report);
    }

    for (final raw in verificationRows) {
      final row = Map<String, dynamic>.from(raw);
      final confirmed = DateTime.tryParse(
        row['confirmed_at']?.toString() ?? '',
      )?.toLocal();
      if (confirmed == null) continue;
      final key = attendanceEventWorkDate(
        confirmed,
        row['daily_reports'],
        workDate: row['work_date'],
      );
      if (key.isBefore(start) || !key.isBefore(end)) continue;
      final draft = drafts.putIfAbsent(key, () => _DayDraft(key));

      final route = row['route_assignments'];
      final routeName = route is Map
          ? route['route_name']?.toString().trim() ?? ''
          : '';
      if (routeName.isNotEmpty && !draft.routeNames.contains(routeName)) {
        draft.routeNames.add(routeName);
      }

      final site = row['sites'];
      if (site is Map &&
          (site['name']?.toString().trim().isNotEmpty ?? false)) {
        draft.siteName ??= site['name'].toString();
      }

      if (row['event_type'] == 'clock_in') {
        if (draft.clockIn == null || confirmed.isBefore(draft.clockIn!)) {
          draft.clockIn = confirmed;
        }
      } else if (row['event_type'] == 'clock_out') {
        if (draft.clockOut == null || confirmed.isAfter(draft.clockOut!)) {
          draft.clockOut = confirmed;
        }
      }
    }

    final allApprovedLeaveRows = await _client
        .from('paid_leave_requests')
        .select('leave_date')
        .eq('worker_id', targetWorkerId)
        .eq('status', 'approved')
        .order('leave_date');

    final summaryRaw = await _client.rpc(
      'paid_leave_worker_summary',
      params: {'p_worker_id': targetWorkerId},
    );
    final summary = summaryRaw is Map
        ? Map<String, dynamic>.from(summaryRaw)
        : const <String, dynamic>{};
    final grantedDays = _number(summary['granted_days']);

    final approvedDates = <DateTime>{
      for (final row in allApprovedLeaveRows)
        if (_parseDate(row['leave_date']?.toString()) case final date?)
          _dateOnly(date),
    }.toList()..sort((a, b) => a.compareTo(b));

    for (var i = 0; i < approvedDates.length; i++) {
      final date = approvedDates[i];
      if (date.isBefore(start) || !date.isBefore(end)) continue;
      final draft = drafts.putIfAbsent(date, () => _DayDraft(date));
      // A corrected work record wins over an older approved paid-leave marker.
      // The approval RPC also cancels the overlapping leave in production.
      if (draft.hasWorkedData) continue;
      draft.paidLeave = true;
      draft.paidLeaveOrdinal = i + 1;
      draft.paidLeaveRemaining = (grantedDays - (i + 1))
          .clamp(0, double.infinity)
          .toDouble();
    }

    final rawUnits = await _client.rpc('my_attendance_allowance_units');
    final allowanceUnits = rawUnits is Map
        ? {
            for (final entry in rawUnits.entries)
              entry.key
                  .toString(): entry.value?.toString().trim().isNotEmpty == true
                  ? entry.value.toString().trim()
                  : '回',
          }
        : <String, String>{};

    return WorkerAttendanceMonth(
      year: month.year,
      month: month.month,
      pendingDetailsUnavailable: pendingDetailsUnavailable,
      allowanceUnits: Map<String, String>.unmodifiable(allowanceUnits),
      days: {
        for (final entry in drafts.entries)
          entry.key: entry.value.toValue(allowanceUnits),
      },
    );
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value.replaceAll('/', '-'));
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  double _number(Object? value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;
}

class _DayDraft {
  _DayDraft(this.date);

  final DateTime date;
  String? siteName;
  final List<String> routeNames = <String>[];
  DateTime? clockIn;
  DateTime? clockOut;
  double overtimeHours = 0;
  double earlyHours = 0;
  double nightHours = 0;
  double manDays = 0;
  bool hasHolidayWork = false;
  int allowanceYen = 0;
  final List<String> allowanceNames = <String>[];
  final List<DailyReportCompanyAllowanceSelection> companyAllowanceSelections =
      [];
  final List<AttendancePendingReportDetails> pendingReports = [];
  bool paidLeave = false;
  int paidLeaveOrdinal = 0;
  double paidLeaveRemaining = 0;

  bool get hasWorkedData => attendanceDayHasWorkedData(
    manDays: manDays,
    overtimeHours: overtimeHours,
    earlyHours: earlyHours,
    nightHours: nightHours,
    siteName: siteName,
    clockIn: clockIn,
    clockOut: clockOut,
  );

  WorkerAttendanceDay toValue(Map<String, String> allowanceUnits) =>
      WorkerAttendanceDay(
        date: date,
        siteName: siteName,
        routeNames: List<String>.unmodifiable(routeNames),
        clockIn: clockIn,
        clockOut: clockOut,
        overtimeHours: overtimeHours,
        earlyHours: earlyHours,
        nightHours: nightHours,
        manDays: manDays,
        hasHolidayWork: hasHolidayWork,
        allowanceYen: allowanceYen,
        allowanceNames: List<String>.unmodifiable(allowanceNames),
        companyAllowanceSelections: List.unmodifiable(
          companyAllowanceSelections,
        ),
        allowanceUnits: Map<String, String>.unmodifiable(allowanceUnits),
        pendingReports: List.unmodifiable(pendingReports),
        paidLeave: paidLeave,
        paidLeaveOrdinal: paidLeaveOrdinal,
        paidLeaveRemaining: paidLeaveRemaining,
      );
}
