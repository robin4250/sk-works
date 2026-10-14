import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'chat_cloud_repository.dart';

class LineSharedGroupsRepository {
  LineSharedGroupsRepository(this.client);
  final SupabaseClient client;
  static LineSharedGroupsRepository? maybeCreate() =>
      SupabaseBackend.isInitialized &&
          SupabaseBackend.client.auth.currentUser != null
      ? LineSharedGroupsRepository(SupabaseBackend.client)
      : null;
  String? get actor => client.auth.currentUser?.id;
  void _check(String? expected) {
    if (expected == null || actor != expected) {
      throw StateError('Session changed');
    }
  }

  Future<List<Map<String, dynamic>>> groups() async {
    final expected = actor;
    _check(expected);
    final value = await client.rpc('line_shared_chat_groups');
    _check(expected);
    if (value is! List) throw StateError('Group metadata unavailable');
    final rows = value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    final previews = await ChatCloudRepository.forClient(client)
      .loadConversationPreviews(rows.map((row) => row['group_id'].toString()));
    _check(expected);
    return [for (final row in rows) {
      ...row,
      'last_message_body': previews[row['group_id']]?.body,
      'last_message_at': previews[row['group_id']]?.sentAt,
    }];
  }

  Stream<String> watchChanges() =>
    ChatCloudRepository.forClient(client).watchConversationChanges();

  Future<ChatConversationSummary?> preview(String groupId) async {
    final expected = actor;
    _check(expected);
    final result = await ChatCloudRepository.forClient(client)
      .loadConversationPreviews([groupId]);
    _check(expected);
    return result[groupId];
  }

  Future<String> company() async {
    final expected = actor;
    _check(expected);
    final rows = await client
        .from('company_members')
        .select('company_id')
        .eq('user_id', expected!)
        .limit(2);
    _check(expected);
    if (rows.length != 1) throw StateError('Company selection unavailable');
    return rows.single['company_id'].toString();
  }

  Future<String> create({
    required String directoryId,
    required String name,
    required String companyId,
    required String origin,
  }) async {
    final expected = actor;
    _check(expected);
    final value = await client.rpc(
      'create_line_shared_chat_group',
      params: {
        'p_directory_id': directoryId,
        'p_name': name,
        'p_origin': origin,
        'p_company_id': companyId,
      },
    );
    _check(expected);
    if (value is! String || value.isEmpty) {
      throw StateError('Group creation unavailable');
    }
    return value;
  }
}
