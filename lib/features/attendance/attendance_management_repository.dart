import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AttendanceManagementOption {
  const AttendanceManagementOption({required this.id, required this.name});
  final String id;
  final String name;
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
}

class AttendanceManagementRepository {
  AttendanceManagementRepository._(this._client);
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
    final rows = await _client.from('company_members').select('company_id,role').eq('user_id', user.id).limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    final companyId = rows.first['company_id']?.toString() ?? '';
    final role = rows.first['role']?.toString() ?? '';
    final permissions = await _client.rpc('current_feature_permissions');
    final canManage = permissions is Map && Map<String, dynamic>.from(permissions)['can_manage_attendance'] == true;
    return (companyId: companyId, allowed: const {'owner', 'admin', 'manager'}.contains(role) && canManage);
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
        verificationQuery = verificationQuery.eq('daily_report_id', reportId);
      } else {
        verificationQuery = verificationQuery
            .gte('confirmed_at', start.toUtc().toIso8601String())
            .lt('confirmed_at', end.toUtc().toIso8601String());
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
        mode: 'work', date: date, workerId: workerId,
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
    return AttendanceManagementCell(mode: 'off', date: date, workerId: workerId);
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
            'notes': notes.trim(),
            'work_description': workDescription.trim(),
            'clock_in': clockIn,
            'clock_out': clockOut,
          },
    ];
    final raw = await _client.rpc('force_manage_attendance', params: {'p_action': action, 'p_items': items});
    return (raw as num?)?.toInt() ?? items.length;
  }

  static double _number(Object? value) => (value as num?)?.toDouble() ?? double.tryParse(value?.toString() ?? '') ?? 0;
  static String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
