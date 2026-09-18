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
        .from('chat_messages')
        .select(
          'id, body, origin, sender_display_name, sent_at, created_at',
        )
        .eq('company_id', companyId)
        .eq('origin', 'line')
        .gte('sent_at', localStart.toUtc().toIso8601String())
        .lt('sent_at', localEnd.toUtc().toIso8601String())
        .order('sent_at');

    return List<Map<String, dynamic>>.from(rows);
  }
}
