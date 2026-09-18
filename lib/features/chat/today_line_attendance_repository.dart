import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class TodayLineAttendanceRepository {
  TodayLineAttendanceRepository._(this._client);

  final SupabaseClient _client;

  static TodayLineAttendanceRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return TodayLineAttendanceRepository._(client);
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

  Future<List<Map<String, dynamic>>> loadTodayLineMessages({
    DateTime? now,
  }) async {
    final companyId = await _companyId();
    final localNow = now ?? DateTime.now();
    final localStart = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
    );
    final localEnd = localStart.add(const Duration(days: 1));

    final rows = await _client
        .from('communication_messages')
        .select(
          'id, body, origin, external_sender_name, created_at, communication_groups(name)',
        )
        .eq('company_id', companyId)
        .eq('origin', 'line')
        .gte('created_at', localStart.toUtc().toIso8601String())
        .lt('created_at', localEnd.toUtc().toIso8601String())
        .order('created_at');

    return List<Map<String, dynamic>>.from(rows);
  }
}
