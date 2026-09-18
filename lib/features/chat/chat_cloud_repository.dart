import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class ChatCloudRepository {
  ChatCloudRepository._(this._client);

  final SupabaseClient _client;

  static ChatCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return ChatCloudRepository._(client);
  }

  String? get currentUserId => _client.auth.currentUser?.id;

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

  Future<List<Map<String, dynamic>>> loadGroups() async {
    final companyId = await _companyId();
    final groupRows = await _client
        .from('communication_groups')
        .select('id, name, site_id, group_type')
        .eq('company_id', companyId)
        .order('name');
    final bindingRows = await _client
        .from('line_group_bindings')
        .select('id, communication_group_id, display_name, status')
        .eq('company_id', companyId);

    final bindingsByGroup = <String, Map<String, dynamic>>{};
    for (final binding in List<Map<String, dynamic>>.from(bindingRows)) {
      final groupId = binding['communication_group_id']?.toString();
      if (groupId != null) {
        bindingsByGroup[groupId] = binding;
      }
    }

    return List<Map<String, dynamic>>.from(groupRows).map((group) {
      final groupId = group['id']?.toString();
      final binding = groupId == null ? null : bindingsByGroup[groupId];
      return <String, dynamic>{
        ...group,
        'line_binding_present': binding != null,
        'line_binding_enabled': binding?['status'] == 'active',
        'line_binding_id': binding?['id'],
        'line_binding_name': binding?['display_name'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> loadSites() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('sites')
        .select('id, name, status')
        .eq('company_id', companyId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? siteId,
  }) async {
    final companyId = await _companyId();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('グループ名を入力してください。');
    }

    final duplicateName = await _client
        .from('communication_groups')
        .select('id')
        .eq('company_id', companyId)
        .eq('name', trimmedName)
        .limit(1);
    if (duplicateName.isNotEmpty) {
      throw StateError('同じグループ名がすでにあります。');
    }

    if (siteId != null) {
      final existingSiteGroup = await _client
          .from('communication_groups')
          .select('id')
          .eq('company_id', companyId)
          .eq('site_id', siteId)
          .limit(1);
      if (existingSiteGroup.isNotEmpty) {
        throw StateError('この現場にはすでに通信グループがあります。');
      }
    }

    final row = await _client
        .from('communication_groups')
        .insert({
          'company_id': companyId,
          'site_id': siteId,
          'name': trimmedName,
          'group_type': siteId == null ? 'company' : 'site',
        })
        .select('id, name, site_id, group_type')
        .single();

    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> beginLineBindingClaim(String groupId) async {
    final response = await _client.rpc(
      'begin_line_group_claim',
      params: {'p_communication_group_id': groupId},
    );

    if (response is List && response.isNotEmpty) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    throw StateError('LINE連携コードを発行できませんでした。');
  }

  Future<void> disableLineBinding(String bindingId) async {
    await _client.rpc(
      'disable_line_group_binding',
      params: {'p_binding_id': bindingId},
    );
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String groupId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('communication_group_id', groupId)
        .order('sent_at')
        .map((rows) => List<Map<String, dynamic>>.from(rows));
  }

  Future<void> sendMessage({
    required String groupId,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return;
    final companyId = await _companyId();
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');

    await _client.from('chat_messages').insert({
      'company_id': companyId,
      'communication_group_id': groupId,
      'body': text,
      'origin': 'sk_works',
      'sender_user_id': user.id,
      'sender_display_name': user.email,
    });
  }

  Future<void> deleteOwnMessage(String id) async {
    await _client.from('chat_messages').delete().eq('id', id);
  }
}
