import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class RolloutReadinessRepository {
  RolloutReadinessRepository._(this._client);

  final SupabaseClient _client;

  static RolloutReadinessRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return RolloutReadinessRepository._(client);
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

  Future<Map<String, dynamic>> loadStatus() async {
    final companyId = await _companyId();

    Future<int> countRows(
      String table, {
      Map<String, Object?> equals = const {},
    }) async {
      var query = _client.from(table).select('id');
      for (final entry in equals.entries) {
        query = query.eq(entry.key, entry.value);
      }
      final rows = await query;
      return rows.length;
    }

    final values = await Future.wait<int>([
      countRows('workers', equals: {
        'company_id': companyId,
        'status': 'active',
      }),
      countRows('sites', equals: {
        'company_id': companyId,
      }),
      countRows('communication_groups', equals: {
        'company_id': companyId,
      }),
      countRows('line_group_bindings', equals: {
        'company_id': companyId,
        'status': 'active',
      }),
      countRows('chat_messages', equals: {
        'company_id': companyId,
        'origin': 'line',
      }),
      countRows('attendance_entries', equals: {
        'company_id': companyId,
      }),
    ]);

    return {
      'company_id': companyId,
      'active_workers': values[0],
      'sites': values[1],
      'communication_groups': values[2],
      'active_line_bindings': values[3],
      'line_messages': values[4],
      'attendance_entries': values[5],
    };
  }
}
