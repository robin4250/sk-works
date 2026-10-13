import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AttendanceCorrectionEntry {
  const AttendanceCorrectionEntry({
    required this.id,
    required this.date,
    required this.workerName,
    required this.siteName,
    required this.workCategory,
    required this.manDays,
    required this.overtimeHours,
    required this.earlyHours,
    required this.nightHours,
    required this.allowanceYen,
    required this.allowanceNames,
    required this.notes,
  });

  final String id;
  final String date;
  final String workerName;
  final String siteName;
  final String workCategory;
  final double manDays;
  final double overtimeHours;
  final double earlyHours;
  final double nightHours;
  final int allowanceYen;
  final List<String> allowanceNames;
  final String notes;

  Map<String, dynamic> snapshot() => {
        'date': date,
        'workerName': workerName,
        'siteName': siteName,
        'workCategory': workCategory,
        'manDays': manDays,
        'overtimeHours': overtimeHours,
        'earlyHours': earlyHours,
        'nightHours': nightHours,
        'allowanceYen': allowanceYen,
        'allowanceNames': allowanceNames,
        'notes': notes,
      };
}

class AttendanceCorrectionRepository {
  AttendanceCorrectionRepository._(this._client);

  final SupabaseClient _client;

  static AttendanceCorrectionRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AttendanceCorrectionRepository._(client);
  }

  Future<({String companyId, bool canManage})> access() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');

    final companyId = rows.first['company_id'].toString();
    final permissions = await _client.rpc('current_feature_permissions');
    final canManage = permissions is Map &&
        permissions['can_manage_attendance'] == true;

    return (companyId: companyId, canManage: canManage);
  }

  Future<List<AttendanceCorrectionEntry>> loadMonth(DateTime month) async {
    final value = await access();
    if (!value.canManage) {
      throw StateError('勤怠修正を利用する権限がありません。');
    }

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1)
        .subtract(const Duration(days: 1));

    final rows = await _client
        .from('attendance_entries')
        .select(
          'id, work_date, work_category, base_man_days, overtime_hours, early_hours, night_hours, allowance_amount, allowance_names, notes, workers(name), sites(name)',
        )
        .eq('company_id', value.companyId)
        .gte('work_date', _dbDate(start))
        .lte('work_date', _dbDate(end))
        .order('work_date', ascending: false)
        .order('created_at', ascending: false);

    return [
      for (final raw in rows)
        AttendanceCorrectionEntry(
          id: raw['id']?.toString() ?? '',
          date: (raw['work_date']?.toString() ?? '').replaceAll('-', '/'),
          workerName: raw['workers'] is Map
              ? (raw['workers'] as Map)['name']?.toString() ?? ''
              : '',
          siteName: raw['sites'] is Map
              ? (raw['sites'] as Map)['name']?.toString() ?? ''
              : '',
          workCategory: raw['work_category']?.toString().trim().isNotEmpty == true
              ? raw['work_category'].toString().trim()
              : 'day',
          manDays: _number(raw['base_man_days']),
          overtimeHours: _number(raw['overtime_hours']),
          earlyHours: _number(raw['early_hours']),
          nightHours: _number(raw['night_hours']),
          allowanceYen: (raw['allowance_amount'] as num?)?.toInt() ?? 0,
          allowanceNames: [
            for (final value in (raw['allowance_names'] as List<dynamic>? ?? const []))
              if (value?.toString().trim().isNotEmpty == true)
                value.toString().trim(),
          ],
          notes: raw['notes']?.toString() ?? '',
        ),
    ].where((entry) => entry.id.isNotEmpty).toList();
  }

  Future<String> createDraft({
    required Iterable<AttendanceCorrectionEntry> originals,
    required Map<String, Map<String, dynamic>> proposedById,
  }) async {
    final value = await access();
    if (!value.canManage) {
      throw StateError('勤怠修正を利用する権限がありません。');
    }
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログイン情報がありません。');

    final selected = originals.toList(growable: false);
    if (selected.isEmpty) {
      throw StateError('修正対象を1件以上選択してください。');
    }

    final request = await _client
        .from('attendance_correction_requests')
        .insert({
          'company_id': value.companyId,
          'requested_by': user.id,
          'status': 'draft',
        })
        .select('id')
        .single();

    final requestId = request['id']?.toString();
    if (requestId == null || requestId.isEmpty) {
      throw StateError('修正申請を作成できませんでした。');
    }

    try {
      await _client.from('attendance_correction_items').insert([
        for (final original in selected)
          {
            'request_id': requestId,
            'company_id': value.companyId,
            'attendance_entry_id': original.id,
            'original_snapshot': original.snapshot(),
            'proposed_snapshot':
                proposedById[original.id] ?? original.snapshot(),
            'change_summary': _changeSummary(
              original.snapshot(),
              proposedById[original.id] ?? original.snapshot(),
            ),
          },
      ]);
    } catch (_) {
      await _client
          .from('attendance_correction_requests')
          .delete()
          .eq('id', requestId);
      rethrow;
    }

    return requestId;
  }

  Future<void> submit({
    required String requestId,
    required String signerName,
    required Object signatureJson,
  }) async {
    await _client.rpc(
      'submit_attendance_correction_request',
      params: {
        'p_request_id': requestId,
        'p_signer_name': signerName.trim(),
        'p_signature_json': signatureJson,
      },
    );
  }

  static String _changeSummary(
    Map<String, dynamic> original,
    Map<String, dynamic> proposed,
  ) {
    final labels = <String, String>{
      'siteName': '現場',
      'workCategory': '勤務区分',
      'manDays': '人工',
      'overtimeHours': '残業',
      'earlyHours': '早出',
      'nightHours': '夜勤',
      'allowanceYen': '旧手当金額',
      'allowanceNames': '手当',
      'notes': '備考',
    };
    final changes = <String>[];
    for (final entry in labels.entries) {
      final before = original[entry.key]?.toString() ?? '';
      final after = proposed[entry.key]?.toString() ?? '';
      if (before != after) {
        changes.add('${entry.value}: $before → $after');
      }
    }
    return changes.join(' / ');
  }

  static double _number(Object? value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;

  static String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
