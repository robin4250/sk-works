import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AttendanceCloudRepository {
  AttendanceCloudRepository._(this._client);

  final SupabaseClient _client;

  static AttendanceCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AttendanceCloudRepository._(client);
  }

  Future<({String companyId, String role})> membership() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');
    final rows = await _client
        .from('company_members')
        .select('company_id, role')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return (
      companyId: rows.first['company_id'] as String,
      role: rows.first['role']?.toString() ?? 'viewer',
    );
  }

  Future<bool> canManageAttendanceEntries() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
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

  Future<List<Map<String, dynamic>>> loadAll() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('attendance_entries')
        .select('id, work_date, base_man_days, overtime_hours, early_hours, night_hours, allowance_amount, notes, workers(name), sites(name)')
        .eq('company_id', companyId)
        .order('work_date', ascending: false)
        .order('created_at', ascending: false);

    return rows.map<Map<String, dynamic>>((row) {
      final worker = row['workers'];
      final site = row['sites'];
      return {
        'id': row['id'],
        'date': _displayDate(row['work_date']?.toString()),
        'workerName': worker is Map ? worker['name'] ?? '' : '',
        'siteName': site is Map ? site['name'] ?? '' : '',
        'manDays': _number(row['base_man_days']),
        'overtimeHours': _number(row['overtime_hours']),
        'earlyHours': _number(row['early_hours']),
        'nightHours': _number(row['night_hours']),
        'allowanceYen': (row['allowance_amount'] as num?)?.toInt() ?? 0,
        'notes': row['notes'] ?? '',
      };
    }).toList();
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> record) async {
    final companyId = await _companyId();
    final workerName = record['workerName']?.toString().trim() ?? '';
    final siteName = record['siteName']?.toString().trim() ?? '';

    if (workerName.isEmpty || siteName.isEmpty) {
      throw StateError('作業員と現場を入力してください。');
    }

    final workers = await _client
        .from('workers')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', workerName)
        .eq('status', 'active')
        .limit(2);
    if (workers.isEmpty) {
      throw StateError('作業員「$workerName」が人員管理に登録されていません。');
    }
    if (workers.length > 1) {
      throw StateError('同名の作業員が複数います。人員管理で識別できるよう整理してください。');
    }

    final sites = await _client
        .from('sites')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', siteName)
        .limit(2);
    if (sites.isEmpty) {
      throw StateError('現場「$siteName」が現場管理に登録されていません。');
    }
    if (sites.length > 1) {
      throw StateError('同名の現場が複数あります。現場名を整理してください。');
    }

    final userId = _client.auth.currentUser?.id;
    final inserted = await _client
        .from('attendance_entries')
        .insert({
          'company_id': companyId,
          'work_date': _dbDate(record['date']),
          'worker_id': workers.first['id'],
          'site_id': sites.first['id'],
          'base_man_days': _number(record['manDays']),
          'overtime_hours': _number(record['overtimeHours']),
          'early_hours': _number(record['earlyHours']),
          'night_hours': _number(record['nightHours']),
          'allowance_amount': (record['allowanceYen'] as num?)?.toInt() ?? 0,
          'notes': _nullable(record['notes']),
          'created_by': userId,
          'updated_by': userId,
        })
        .select('id')
        .single();

    return {...record, 'id': inserted['id']};
  }

  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _client.from('attendance_entries').delete().eq('id', id);
  }

  double _number(Object? value) => (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  String _displayDate(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.replaceAll('-', '/');
  }

  String _dbDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) throw StateError('日付を入力してください。');
    return text.replaceAll('/', '-');
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
