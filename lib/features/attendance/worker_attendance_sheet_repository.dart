import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class WorkerAttendanceDay {
  const WorkerAttendanceDay({
    required this.date,
    this.siteName,
    this.clockIn,
    this.clockOut,
    this.overtimeHours = 0,
    this.earlyHours = 0,
    this.nightHours = 0,
    this.allowanceYen = 0,
    this.allowanceNames = const <String>[],
    this.allowanceUnits = const <String, String>{},
  });

  final DateTime date;
  final String? siteName;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final int allowanceYen;
  final List<String> allowanceNames;
  final Map<String, String> allowanceUnits;

  bool get hasAllowance => allowanceNames.isNotEmpty || allowanceYen > 0;

  bool get worked =>
      (siteName?.trim().isNotEmpty ?? false) || clockIn != null || clockOut != null;
}

class WorkerAttendanceMonth {
  const WorkerAttendanceMonth({
    required this.year,
    required this.month,
    required this.days,
    this.allowanceUnits = const <String, String>{},
  });

  final int year;
  final int month;
  final Map<DateTime, WorkerAttendanceDay> days;
  final Map<String, String> allowanceUnits;

  int get workedDays => days.values.where((day) => day.worked).length;

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

  final SupabaseClient _client;

  static WorkerAttendanceSheetRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return WorkerAttendanceSheetRepository._(client);
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
      findDailyReportForDate(
    DateTime date,
  ) async {
    final workerId = await ensureCurrentWorkerId();
    final rows = await _client
        .from('daily_report_workers')
        .select(
          'report_id,daily_reports!inner(site_id,route_assignment_id,report_date)',
        )
        .eq('worker_id', workerId)
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
      routeAssignmentId:
          routeAssignmentId?.isEmpty == true ? null : routeAssignmentId,
    );
  }

  Future<WorkerAttendanceMonth> loadMonth(DateTime month) async {
    final workerId = await ensureCurrentWorkerId();
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final startText = _dbDate(start);
    final endText = _dbDate(end);

    final attendanceRows = await _client
        .from('attendance_entries')
        .select(
          'id, work_date, site_id, overtime_hours, early_hours, night_hours, allowance_amount, allowance_names, sites(name)',
        )
        .eq('worker_id', workerId)
        .gte('work_date', startText)
        .lt('work_date', endText)
        .order('work_date');

    final verificationRows = await _client
        .from('attendance_verifications')
        .select(
          'event_type, confirmed_at, site_id, sites(name)',
        )
        .eq('worker_id', workerId)
        .gte('confirmed_at', start.toUtc().toIso8601String())
        .lt('confirmed_at', end.toUtc().toIso8601String())
        .order('confirmed_at');

    final drafts = <DateTime, _DayDraft>{};

    for (final raw in attendanceRows) {
      final row = Map<String, dynamic>.from(raw);
      final date = _parseDate(row['work_date']?.toString());
      if (date == null) continue;
      final key = _dateOnly(date);
      final draft = drafts.putIfAbsent(key, () => _DayDraft(key));

      final site = row['sites'];
      if (site is Map && (site['name']?.toString().trim().isNotEmpty ?? false)) {
        draft.siteName ??= site['name'].toString();
      }
      draft.overtimeHours += _number(row['overtime_hours']);
      draft.earlyHours += _number(row['early_hours']);
      draft.nightHours += _number(row['night_hours']);
      draft.allowanceYen += (row['allowance_amount'] as num?)?.toInt() ?? 0;
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

    for (final raw in verificationRows) {
      final row = Map<String, dynamic>.from(raw);
      final confirmed = DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
      if (confirmed == null) continue;
      final key = _dateOnly(confirmed);
      final draft = drafts.putIfAbsent(key, () => _DayDraft(key));

      final site = row['sites'];
      if (site is Map && (site['name']?.toString().trim().isNotEmpty ?? false)) {
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

    final rawUnits = await _client.rpc('my_attendance_allowance_units');
    final allowanceUnits = rawUnits is Map
        ? {
            for (final entry in rawUnits.entries)
              entry.key.toString(): entry.value?.toString().trim().isNotEmpty == true
                  ? entry.value.toString().trim()
                  : '回',
          }
        : <String, String>{};

    return WorkerAttendanceMonth(
      year: month.year,
      month: month.month,
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
  DateTime? clockIn;
  DateTime? clockOut;
  double overtimeHours = 0;
  double earlyHours = 0;
  double nightHours = 0;
  int allowanceYen = 0;
  final List<String> allowanceNames = <String>[];

  WorkerAttendanceDay toValue(Map<String, String> allowanceUnits) =>
      WorkerAttendanceDay(
        date: date,
        siteName: siteName,
        clockIn: clockIn,
        clockOut: clockOut,
        overtimeHours: overtimeHours,
        earlyHours: earlyHours,
        nightHours: nightHours,
        allowanceYen: allowanceYen,
        allowanceNames: List<String>.unmodifiable(allowanceNames),
        allowanceUnits: Map<String, String>.unmodifiable(allowanceUnits),
      );
}
