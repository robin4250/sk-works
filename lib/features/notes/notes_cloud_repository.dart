import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class NotesCloudRepository {
  NotesCloudRepository._(this._client);

  final SupabaseClient _client;

  static NotesCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return NotesCloudRepository._(client);
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SK WORKSへのログインが必要です。');

    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return rows.first['company_id'] as String;
  }

  Future<List<Map<String, dynamic>>> loadGroups() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('communication_groups')
        .select('id, name, site_id, group_type')
        .eq('company_id', companyId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadNotes(String groupId) async {
    final companyId = await _companyId();
    final rows = await _client
        .from('communication_notes')
        .select('id, group_id, title, body, is_pinned, created_at, updated_at')
        .eq('company_id', companyId)
        .eq('group_id', groupId)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> insertNote({
    required String groupId,
    required String title,
    String? body,
    bool isPinned = false,
  }) async {
    final companyId = await _companyId();
    final user = _client.auth.currentUser;
    final inserted = await _client
        .from('communication_notes')
        .insert({
          'company_id': companyId,
          'group_id': groupId,
          'title': title.trim(),
          'body': _nullable(body),
          'is_pinned': isPinned,
          'created_by': user?.id,
        })
        .select('id, group_id, title, body, is_pinned, created_at, updated_at')
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<void> setPinned(String id, bool value) async {
    await _client
        .from('communication_notes')
        .update({'is_pinned': value, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  Future<void> deleteNote(String id) async {
    await _client.from('communication_notes').delete().eq('id', id);
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
