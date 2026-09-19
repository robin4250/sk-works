import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class ChatCloudRepository {
  ChatCloudRepository._(this._client);

  final SupabaseClient _client;
  static const _attachmentBucket = 'chat-attachments';

  static ChatCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return ChatCloudRepository._(client);
  }

  String? get currentUserId => _client.auth.currentUser?.id;

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

  Future<String> _companyId() async => (await membership()).companyId;

  Future<List<Map<String, dynamic>>> loadGroups() async {
    final value = await membership();
    final canManageLineBinding =
        value.role == 'owner' || value.role == 'admin';

    final groupRows = await _client
        .from('communication_groups')
        .select(
          'id, name, site_id, group_type, last_activity_at, sites(name)',
        )
        .eq('company_id', value.companyId)
        .order('last_activity_at', ascending: false);

    final bindingRows = await _client
        .from('line_group_bindings')
        .select('id, communication_group_id, display_name, status')
        .eq('company_id', value.companyId);

    final directMembershipRows = await _client
        .from('communication_group_members')
        .select('group_id, user_id')
        .eq('company_id', value.companyId);

    final memberProfileRows = await _client.rpc('company_member_profiles');

    final profileByUser = <String, Map<String, dynamic>>{};
    for (final raw in (memberProfileRows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final userId = row['user_id']?.toString();
      if (userId != null) profileByUser[userId] = row;
    }

    final directUsersByGroup = <String, List<String>>{};
    for (final raw in directMembershipRows) {
      final groupId = raw['group_id']?.toString();
      final userId = raw['user_id']?.toString();
      if (groupId == null || userId == null) continue;
      directUsersByGroup.putIfAbsent(groupId, () => []).add(userId);
    }

    final bindingsByGroup = <String, Map<String, dynamic>>{};
    for (final binding in List<Map<String, dynamic>>.from(bindingRows)) {
      final groupId = binding['communication_group_id']?.toString();
      if (groupId != null) bindingsByGroup[groupId] = binding;
    }

    final myId = currentUserId;
    final groups = <Map<String, dynamic>>[];

    for (final raw in groupRows) {
      final group = Map<String, dynamic>.from(raw);
      final groupId = group['id']?.toString() ?? '';
      final binding = bindingsByGroup[groupId];
      final site = group['sites'];

      String displayName = group['name']?.toString() ?? '';
      String? avatarPath;
      String? directOtherUserId;

      if (group['group_type'] == 'direct') {
        final members = directUsersByGroup[groupId] ?? const [];
        final otherId = members.firstWhere(
          (id) => id != myId,
          orElse: () => '',
        );
        directOtherUserId = otherId.isEmpty ? null : otherId;
        final profile = profileByUser[otherId];
        displayName = profile?['display_name']?.toString() ?? '個別トーク';
        avatarPath = profile?['avatar_storage_path']?.toString();
      } else if (group['group_type'] == 'site' && site is Map) {
        displayName = site['name']?.toString() ?? displayName;
      }

      String? avatarUrl;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        try {
          avatarUrl = await _client.storage
              .from('profile-photos')
              .createSignedUrl(avatarPath, 3600);
        } catch (_) {
          avatarUrl = null;
        }
      }

      groups.add({
        ...group,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'direct_other_user_id': directOtherUserId,
        'line_binding_present': binding != null,
        'line_binding_enabled': binding?['status'] == 'active',
        'line_binding_id': binding?['id'],
        'line_binding_name': binding?['display_name'],
        'line_binding_can_manage': canManageLineBinding,
      });
    }

    return groups;
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

  Future<List<Map<String, dynamic>>> loadMembers() async {
    final rows = await _client.rpc('company_member_profiles');
    final list = <Map<String, dynamic>>[];

    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['user_id']?.toString() == currentUserId) continue;

      String? avatarUrl;
      final path = row['avatar_storage_path']?.toString();
      if (path != null && path.isNotEmpty) {
        try {
          avatarUrl = await _client.storage
              .from('profile-photos')
              .createSignedUrl(path, 3600);
        } catch (_) {
          avatarUrl = null;
        }
      }

      list.add({
        ...row,
        'avatar_url': avatarUrl,
      });
    }
    return list;
  }

  Future<List<String>> prioritizedSiteGroupIds() async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    final groups = await loadGroups();
    final siteGroups = groups
        .where((group) => group['group_type'] == 'site')
        .toList();

    final messageRows = await _client
        .from('chat_messages')
        .select('communication_group_id, sent_at')
        .eq('sender_user_id', user.id)
        .order('sent_at', ascending: false)
        .limit(200);

    final spoken = <String>[];
    for (final raw in messageRows) {
      final id = raw['communication_group_id']?.toString();
      if (id != null && !spoken.contains(id)) spoken.add(id);
    }

    String? workerId;
    try {
      final value = await _client.rpc('ensure_current_user_worker');
      workerId = value?.toString();
    } catch (_) {
      workerId = null;
    }

    final attended = <String>[];
    if (workerId != null && workerId.isNotEmpty) {
      final attendanceRows = await _client
          .from('attendance_verifications')
          .select('site_id, confirmed_at')
          .eq('worker_id', workerId)
          .eq('event_type', 'clock_in')
          .order('confirmed_at', ascending: false)
          .limit(100);

      final groupBySite = <String, String>{
        for (final group in siteGroups)
          if (group['site_id'] != null)
            group['site_id'].toString(): group['id'].toString(),
      };

      for (final raw in attendanceRows) {
        final siteId = raw['site_id']?.toString();
        final groupId = siteId == null ? null : groupBySite[siteId];
        if (groupId != null && !attended.contains(groupId)) {
          attended.add(groupId);
        }
      }
    }

    return [
      ...spoken.where(
        (id) => siteGroups.any((group) => group['id']?.toString() == id),
      ),
      ...attended.where((id) => !spoken.contains(id)),
      ...siteGroups
          .map((group) => group['id'].toString())
          .where((id) => !spoken.contains(id) && !attended.contains(id)),
    ];
  }

  Future<String> startDirectChat(String otherUserId) async {
    final value = await _client.rpc(
      'start_direct_chat',
      params: {'p_other_user_id': otherUserId},
    );
    final id = value?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('個別トークを開始できませんでした。');
    }
    return id;
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    String? siteId,
    String groupType = 'company',
  }) async {
    final companyId = await _companyId();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw StateError('グループ名を入力してください。');
    }

    final row = await _client
        .from('communication_groups')
        .insert({
          'company_id': companyId,
          'site_id': siteId,
          'name': trimmedName,
          'group_type': siteId != null ? 'site' : groupType,
          'last_activity_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('id, name, site_id, group_type, last_activity_at')
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
        .asyncMap((rows) async {
          final messages = List<Map<String, dynamic>>.from(rows);
          if (messages.isEmpty) return messages;

          final ids = messages.map((row) => row['id'].toString()).toList();

          final attachmentRows = await _client
              .from('chat_attachments')
              .select(
                'id, message_id, storage_path, original_filename, mime_type, attachment_type',
              )
              .inFilter('message_id', ids);

          final attachmentsByMessage = <String, List<Map<String, dynamic>>>{};
          for (final raw in attachmentRows) {
            final row = Map<String, dynamic>.from(raw);
            final messageId = row['message_id']?.toString();
            if (messageId == null) continue;

            try {
              row['signed_url'] = await _client.storage
                  .from(_attachmentBucket)
                  .createSignedUrl(row['storage_path'].toString(), 3600);
            } catch (_) {
              row['signed_url'] = null;
            }

            attachmentsByMessage
                .putIfAbsent(messageId, () => [])
                .add(row);
          }

          return [
            for (final message in messages)
              {
                ...message,
                'attachments':
                    attachmentsByMessage[message['id']?.toString()] ??
                        const <Map<String, dynamic>>[],
              },
          ];
        });
  }

  Future<String> sendMessage({
    required String groupId,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return '';
    final companyId = await _companyId();
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');

    final profiles = await _client
        .from('user_profiles')
        .select('display_name')
        .eq('user_id', user.id)
        .limit(1);
    final displayName = profiles.isEmpty
        ? user.phone ?? user.email ?? 'メンバー'
        : profiles.first['display_name']?.toString() ?? 'メンバー';

    final row = await _client
        .from('chat_messages')
        .insert({
          'company_id': companyId,
          'communication_group_id': groupId,
          'body': text,
          'origin': 'sk_works',
          'sender_user_id': user.id,
          'sender_display_name': displayName,
        })
        .select('id')
        .single();

    return row['id']?.toString() ?? '';
  }

  Future<void> sendAttachment({
    required String groupId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required bool isImage,
  }) async {
    final companyId = await _companyId();
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('SKOへのログインが必要です。');

    final messageId = await sendMessage(
      groupId: groupId,
      body: isImage ? '写真を送信しました' : filename,
    );
    if (messageId.isEmpty) {
      throw StateError('添付メッセージを作成できませんでした。');
    }

    final safeName = filename
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final storagePath =
        '$companyId/$groupId/$messageId/${DateTime.now().microsecondsSinceEpoch}-$safeName';

    await _client.storage.from(_attachmentBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: mimeType,
          ),
        );

    try {
      await _client.from('chat_attachments').insert({
        'company_id': companyId,
        'communication_group_id': groupId,
        'message_id': messageId,
        'storage_path': storagePath,
        'original_filename': filename,
        'mime_type': mimeType,
        'attachment_type': isImage ? 'image' : 'file',
        'uploaded_by': user.id,
      });
    } catch (_) {
      await _client.storage.from(_attachmentBucket).remove([storagePath]);
      rethrow;
    }
  }

  Future<void> deleteOwnMessage(String id) async {
    await _client.from('chat_messages').delete().eq('id', id);
  }
}
