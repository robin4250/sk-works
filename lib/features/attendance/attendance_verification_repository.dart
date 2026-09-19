import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class AttendanceVerificationRepository {
  AttendanceVerificationRepository._(this._client);

  final SupabaseClient _client;
  static const _bucket = 'attendance-evidence';

  static AttendanceVerificationRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AttendanceVerificationRepository._(client);
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

  Future<bool> canManageAttendance() async {
    final value = await _client.rpc('current_feature_permissions');
    if (value is! Map) return false;
    final permissions = Map<String, dynamic>.from(value);
    return permissions['can_manage_attendance'] == true;
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final companyId = await _companyId();
    final row = await _client
        .from('attendance_verification_settings')
        .select('company_id, mode, proximity_radius_m')
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) {
      return {
        'company_id': companyId,
        'mode': 'manual',
        'proximity_radius_m': 300,
      };
    }
    return Map<String, dynamic>.from(row);
  }

  Future<void> saveSettings({
    required String mode,
    required int proximityRadiusM,
  }) async {
    if (!await canManageAttendance()) {
      throw StateError('出勤確認方法を変更する権限がありません。');
    }
    final companyId = await _companyId();
    await _client.from('attendance_verification_settings').upsert({
      'company_id': companyId,
      'mode': mode,
      'proximity_radius_m': proximityRadiusM,
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadWorkers() async {
    final companyId = await _companyId();

    if (await canManageAttendance()) {
      final rows = await _client
          .from('workers')
          .select('id, name')
          .eq('company_id', companyId)
          .eq('status', 'active')
          .order('name');
      return List<Map<String, dynamic>>.from(rows);
    }

    final workerId = await _client.rpc('ensure_current_user_worker');
    final id = workerId?.toString();
    if (id == null || id.isEmpty) return const [];

    final rows = await _client
        .from('workers')
        .select('id, name')
        .eq('company_id', companyId)
        .eq('id', id)
        .limit(1);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadSites() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('sites')
        .select('id, name, address, latitude, longitude, status')
        .eq('company_id', companyId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> updateSiteLocation({
    required String siteId,
    required double latitude,
    required double longitude,
  }) async {
    if (!await canManageAttendance()) {
      throw StateError('現場の基準位置を変更する権限がありません。');
    }

    await _client.rpc(
      'update_site_attendance_location',
      params: {
        'p_site_id': siteId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
  }

  Future<List<Map<String, dynamic>>> loadRecent({int limit = 20}) async {
    final companyId = await _companyId();
    final rows = await _client
        .from('attendance_verifications')
        .select(
          'id, event_type, verification_mode, confirmed_at, '
          'proximity_status, distance_to_site_m, workers(name), sites(name)',
        )
        .eq('company_id', companyId)
        .order('confirmed_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createVerification({
    required String workerId,
    required String siteId,
    required String eventType,
    required String verificationMode,
    double? latitude,
    double? longitude,
    double? accuracyM,
    double? distanceToSiteM,
    required String proximityStatus,
    Uint8List? photoBytes,
    String? photoFilename,
    String? note,
  }) async {
    final companyId = await _companyId();
    String? storagePath;

    if (photoBytes != null) {
      final extension = _extensionOf(photoFilename ?? 'attendance.jpg');
      final objectName =
          '${DateTime.now().microsecondsSinceEpoch}$extension';
      storagePath =
          '$companyId/attendance/$siteId/$workerId/$objectName';
      await _client.storage.from(_bucket).uploadBinary(
            storagePath,
            photoBytes,
            fileOptions: const FileOptions(upsert: false),
          );
    }

    try {
      final row = await _client
          .from('attendance_verifications')
          .insert({
            'company_id': companyId,
            'worker_id': workerId,
            'site_id': siteId,
            'event_type': eventType,
            'verification_mode': verificationMode,
            'latitude': latitude,
            'longitude': longitude,
            'accuracy_m': accuracyM,
            'distance_to_site_m': distanceToSiteM,
            'proximity_status': proximityStatus,
            'photo_storage_path': storagePath,
            'note': _nullable(note),
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id, confirmed_at')
          .single();
      return Map<String, dynamic>.from(row);
    } catch (_) {
      if (storagePath != null) {
        await _client.storage.from(_bucket).remove([storagePath]);
      }
      rethrow;
    }
  }

  String _extensionOf(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot < 0 || lastDot == filename.length - 1) return '.jpg';
    final ext = filename.substring(lastDot).toLowerCase();
    if (ext.length > 8) return '.jpg';
    final cleaned = ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
    return cleaned.isEmpty ? '.jpg' : cleaned;
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
