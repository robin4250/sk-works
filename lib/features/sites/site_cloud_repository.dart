import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class SitePhotoRecord {
  const SitePhotoRecord({
    required this.slot,
    required this.storagePath,
    required this.signedUrl,
  });

  final int slot;
  final String storagePath;
  final String signedUrl;
}

class SiteCloudRepository {
  SiteCloudRepository._(this._client);

  final SupabaseClient _client;

  static SiteCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return SiteCloudRepository._(client);
  }

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

  Future<bool> canManageSites() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
  }

  Future<bool> canCreateSites() async {
    final value = await membership();
    return value.role != 'viewer';
  }

  Future<List<Map<String, dynamic>>> loadAll() async {
    final raw = await _client.rpc('site_directory_rows_v2');
    final rows = raw is List
        ? raw
        : raw is Map && raw['rows'] is List
            ? raw['rows'] as List<dynamic>
            : const <dynamic>[];

    final metadataRaw = await _client.rpc('site_directory_metadata');
    final metadata = metadataRaw is Map
        ? Map<String, dynamic>.from(metadataRaw)
        : const <String, dynamic>{};
    final creatorBySite = <String, String>{};
    final creators = metadata['creators'];
    if (creators is List) {
      for (final item in creators) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['site_id']?.toString() ?? '';
        if (id.isNotEmpty) {
          creatorBySite[id] = map['creator_name']?.toString() ?? '';
        }
      }
    }

    final siteDates = <String, Map<String, dynamic>>{};
    final dateRows =
        await _client.from('sites').select('id,created_at,updated_at');
    for (final item in dateRows) {
      final id = item['id']?.toString() ?? '';
      if (id.isNotEmpty) siteDates[id] = Map<String, dynamic>.from(item);
    }

    return rows.map<Map<String, dynamic>>((rawRow) {
      final row = Map<String, dynamic>.from(rawRow as Map);
      final id = row['id']?.toString() ?? '';
      final dates = siteDates[id] ?? const <String, dynamic>{};
      return {
        'id': id,
        'name': row['name'] ?? '',
        'customerName': row['customer_name'] ?? '',
        'status': _fromDbStatus(row['status']?.toString()),
        'address': row['address'] ?? '',
        'managerName': row['manager_name'] ?? '',
        'startDate': _displayDate(row['starts_at']?.toString()),
        'endDate': _displayDate(row['ends_at']?.toString()),
        'notes': row['notes'] ?? '',
        'formalName': row['formal_name'] ?? '',
        'nearestStation': row['nearest_station'] ?? '',
        'representativeName': row['representative_name'] ?? '',
        'representativePhone': row['representative_phone'] ?? '',
        'creatorName': creatorBySite[id] ?? '',
        'createdAt': _displayDateTime(dates['created_at']?.toString()),
        'updatedAt': _displayDateTime(dates['updated_at']?.toString()),
      };
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> record) async {
    final customerName = record['customerName']?.toString().trim() ?? '';
    final siteName = record['name']?.toString().trim() ?? '';
    if (siteName.isEmpty) throw StateError('現場名を入力してください。');
    if (customerName.isEmpty) throw StateError('取引先を入力してください。');

    final insertedId = await _client.rpc(
      'save_site_directory_v2',
      params: {'p_record': {...record, 'id': null}},
    );

    return {...record, 'id': insertedId?.toString() ?? ''};
  }

  Future<void> submitInformationChange({
    required String siteId,
    required Map<String, String> values,
  }) async {
    if (siteId.isEmpty) throw StateError('現場を確認できません。');
    await _client.rpc(
      'site_information_request',
      params: {
        'p_action': 'submit',
        'p_data': {'site_id': siteId, 'values': values},
      },
    );
  }

  Future<List<Map<String, dynamic>>> loadInformationRequests() async {
    final raw = await _client.rpc(
      'site_information_request',
      params: {'p_action': 'list', 'p_data': <String, dynamic>{}},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> reviewInformationRequest({
    required String requestId,
    required bool approve,
    String reason = '',
  }) async {
    await _client.rpc(
      'site_information_request',
      params: {
        'p_action': approve ? 'approve' : 'reject',
        'p_data': {'id': requestId, if (!approve) 'reason': reason},
      },
    );
  }

  Future<List<SitePhotoRecord>> loadPhotos(String siteId) async {
    final rows = await _client
        .from('site_entrance_photos')
        .select('slot,storage_path')
        .eq('site_id', siteId)
        .order('slot');
    final bucket = _client.storage.from('site-entrance-photos');
    final result = <SitePhotoRecord>[];
    for (final row in rows) {
      final path = row['storage_path']?.toString() ?? '';
      if (path.isEmpty) continue;
      final url = await bucket.createSignedUrl(path, 3600);
      result.add(
        SitePhotoRecord(
          slot: (row['slot'] as num?)?.toInt() ?? 0,
          storagePath: path,
          signedUrl: url,
        ),
      );
    }
    return result;
  }

  Future<bool> uploadPhoto({
    required String siteId,
    required int slot,
    required Uint8List bytes,
  }) async {
    if (slot < 1 || slot > 3) throw StateError('写真は3枚までです。');
    final prepared = await _client.rpc(
      'site_photo_request',
      params: {
        'p_action': 'prepare',
        'p_data': {'site_id': siteId, 'slot': slot},
      },
    );
    final map = prepared is Map
        ? Map<String, dynamic>.from(prepared)
        : const <String, dynamic>{};
    final requestId = map['id']?.toString() ?? '';
    final uploadPath = map['upload_path']?.toString() ?? '';
    if (requestId.isEmpty || uploadPath.isEmpty) {
      throw StateError('写真の登録準備に失敗しました。');
    }

    await _client.storage.from('site-entrance-photos').uploadBinary(
          uploadPath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
    final submitted = await _client.rpc(
      'site_photo_request',
      params: {
        'p_action': 'submit',
        'p_data': {'id': requestId},
      },
    );
    final submitMap = submitted is Map
        ? Map<String, dynamic>.from(submitted)
        : const <String, dynamic>{};
    return submitMap['pending'] == true;
  }

  Future<List<Map<String, dynamic>>> loadPhotoRequests() async {
    final raw = await _client.rpc(
      'site_photo_request',
      params: {'p_action': 'list', 'p_data': <String, dynamic>{}},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> reviewPhotoRequest({
    required String requestId,
    required bool approve,
    String reason = '',
  }) async {
    await _client.rpc(
      'site_photo_request',
      params: {
        'p_action': approve ? 'approve' : 'reject',
        'p_data': {'id': requestId, if (!approve) 'reason': reason},
      },
    );
  }

  Future<Map<String, dynamic>?> loadCreatorEmployee(String creatorName) async {
    final name = creatorName.trim();
    if (name.isEmpty) return null;
    final member = await membership();
    final rows = await _client
        .from('workers')
        .select('id,name,kana,phone,email,status,role,experience_years,created_at,updated_at')
        .eq('company_id', member.companyId)
        .eq('name', name)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> complete(String id) async {
    if (id.isEmpty) return;
    await _client.from('sites').update({
      'status': 'completed',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  String _fromDbStatus(String? value) => switch (value) {
        'active' => 'active',
        'paused' => 'paused',
        'completed' => 'completed',
        _ => 'preparing',
      };

  String _displayDate(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.replaceAll('-', '/');
  }

  String _displayDateTime(String? value) {
    if (value == null || value.isEmpty) return '';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}/${two(parsed.month)}/${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }
}
