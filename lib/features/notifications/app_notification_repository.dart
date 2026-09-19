import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AppNotificationRecord {
  const AppNotificationRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.actionKey,
    this.actionId,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? actionKey;
  final String? actionId;

  factory AppNotificationRecord.fromRow(Map<String, dynamic> row) {
    return AppNotificationRecord(
      id: row['id']?.toString() ?? '',
      kind: row['kind']?.toString() ?? 'info',
      title: row['title']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: row['read_at'] != null,
      actionKey: row['action_key']?.toString(),
      actionId: row['action_id']?.toString(),
    );
  }
}

class AppNotificationRepository {
  AppNotificationRepository._(this._client);

  final SupabaseClient _client;

  static AppNotificationRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AppNotificationRepository._(client);
  }

  Future<List<AppNotificationRecord>> load({int limit = 100}) async {
    final rows = await _client
        .from('app_notifications')
        .select(
          'id, kind, title, body, action_key, action_id, read_at, created_at',
        )
        .order('created_at', ascending: false)
        .limit(limit);

    return rows
        .map<AppNotificationRecord>(
          (row) => AppNotificationRecord.fromRow(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<int> unreadCount() async {
    final rows = await _client
        .from('app_notifications')
        .select('id')
        .isFilter('read_at', null);
    return rows.length;
  }

  Future<void> markRead(String id) async {
    if (id.isEmpty) return;
    await _client
        .from('app_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> markAllRead() async {
    await _client.rpc('mark_all_notifications_read');
  }
}
