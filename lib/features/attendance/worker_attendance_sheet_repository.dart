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
  });

  final DateTime date;
  final String? siteName;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final int allowanceYen;

  bool get worked =>
      (siteName?.trim().isNotEmpty ?? false) || clockIn != null || clockOut != null;
}

class WorkerAttendanceMonth {
  const WorkerAttendanceMonth({
    required this.year,
    required this.month,
    required this.days,
  });

  final int year;
  final int month;
  final Map<DateTime, WorkerAttendanceDay> days;

  int get workedDays => days.values.where((day) => day.worked).length;

  double get overtimeHours =>
      days.values.fold(0, (sum, day) => sum + day.overtimeHours);

  double get earlyHours =>
      days.values.fold(0, (sum, day) => sum + day.earlyHours);

  double get nightHours =>
      days.values.fold(0, (sum, day) => sum + day.nightHours);

  int get allowanceYen =>
      days.values.fold(0, (sum, day) => sum + day.allowanceYen);
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

  Future<WorkerAttendanceMonth> loadMonth(DateTime month) async {
    final workerId = await ensureCurrentWorkerId();
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final startText = _dbDate(start);
    final endText = _dbDate(end);

    final attendanceRows = await _client
        .from('attendance_entries')
        .select(
          'id, work_date, site_id, overtime_hours, early_hours, night_hours, allowance_amount, sites(name)',
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

    return WorkerAttendanceMonth(
      year: month.year,
      month: month.month,
      days: {
        for (final entry in drafts.entries)
          entry.key: entry.value.toValue(),
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

  WorkerAttendanceDay toValue() => WorkerAttendanceDay(
        date: date,
        siteName: siteName,
        clockIn: clockIn,
        clockOut: clockOut,
        overtimeHours: overtimeHours,
        earlyHours: earlyHours,
        nightHours: nightHours,
        allowanceYen: allowanceYen,
      );
}
