import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AlbumsCloudRepository {
  AlbumsCloudRepository._(this._client);

  final SupabaseClient _client;
  static const _bucket = 'communication-albums';

  static AlbumsCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AlbumsCloudRepository._(client);
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

  Future<List<Map<String, dynamic>>> loadAlbums(String groupId) async {
    final companyId = await _companyId();
    final rows = await _client
        .from('communication_albums')
        .select('id, group_id, name, description, created_at, updated_at')
        .eq('company_id', companyId)
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createAlbum({
    required String groupId,
    required String name,
    String? description,
  }) async {
    final companyId = await _companyId();
    final user = _client.auth.currentUser;
    final row = await _client
        .from('communication_albums')
        .insert({
          'company_id': companyId,
          'group_id': groupId,
          'name': name.trim(),
          'description': _nullable(description),
          'created_by': user?.id,
        })
        .select('id, group_id, name, description, created_at, updated_at')
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> loadItems(String albumId) async {
    final companyId = await _companyId();
    final rows = await _client
        .from('communication_album_items')
        .select('id, group_id, album_id, storage_path, caption, original_filename, created_at')
        .eq('company_id', companyId)
        .eq('album_id', albumId)
        .order('created_at', ascending: false);

    final items = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final item = Map<String, dynamic>.from(raw);
      item['signed_url'] = await _client.storage
          .from(_bucket)
          .createSignedUrl(item['storage_path'] as String, 60 * 60);
      items.add(item);
    }
    return items;
  }

  Future<void> uploadPhoto({
    required String groupId,
    required String albumId,
    required Uint8List bytes,
    required String originalFilename,
    String? caption,
  }) async {
    final companyId = await _companyId();
    final user = _client.auth.currentUser;
    final extension = _extensionOf(originalFilename);
    final objectName = '${DateTime.now().microsecondsSinceEpoch}-$albumId$extension';
    final storagePath = '$companyId/$groupId/$albumId/$objectName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    try {
      await _client.from('communication_album_items').insert({
        'company_id': companyId,
        'group_id': groupId,
        'album_id': albumId,
        'storage_path': storagePath,
        'caption': _nullable(caption),
        'original_filename': originalFilename,
        'uploaded_by': user?.id,
      });
    } catch (_) {
      await _client.storage.from(_bucket).remove([storagePath]);
      rethrow;
    }
  }

  Future<void> deleteItem(Map<String, dynamic> item) async {
    final storagePath = item['storage_path'] as String;
    await _client.storage.from(_bucket).remove([storagePath]);
    await _client
        .from('communication_album_items')
        .delete()
        .eq('id', item['id'] as String);
  }

  Future<void> deleteAlbum(String albumId) async {
    final rows = await _client
        .from('communication_album_items')
        .select('storage_path')
        .eq('album_id', albumId);
    final paths = rows
        .map((row) => row['storage_path'])
        .whereType<String>()
        .toList(growable: false);
    if (paths.isNotEmpty) {
      await _client.storage.from(_bucket).remove(paths);
    }
    await _client.from('communication_albums').delete().eq('id', albumId);
  }

  String _extensionOf(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot < 0 || lastDot == filename.length - 1) return '.jpg';
    final ext = filename.substring(lastDot).toLowerCase();
    if (ext.length > 8) return '.jpg';
    return ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
