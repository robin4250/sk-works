import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class QualificationCertificateRepository {
  QualificationCertificateRepository._(this._client);

  final SupabaseClient _client;
  static const _bucket = 'qualification-certificates';

  static QualificationCertificateRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return QualificationCertificateRepository._(client);
  }

  Future<bool> canManageCertificates() async {
    final value = await _client.rpc('current_feature_permissions');
    if (value is! Map) return false;
    final permissions = Map<String, dynamic>.from(value);
    return permissions['can_manage_people'] == true;
  }

  Future<void> _requireManagePeople() async {
    if (!await canManageCertificates()) {
      throw StateError('資格証を変更する権限がありません。');
    }
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

  Future<Map<String, dynamic>> loadAll() async {
    final companyId = await _companyId();
    final canManage = await canManageCertificates();

    String? ownWorkerId;
    if (!canManage) {
      final value = await _client.rpc('ensure_current_user_worker');
      ownWorkerId = value?.toString();
    }

    final masters = await _client
        .from('qualification_master')
        .select('id, name, issuer')
        .eq('company_id', companyId)
        .order('name');

    var workersQuery = _client
        .from('workers')
        .select('id, name, affiliation, status')
        .eq('company_id', companyId);
    if (!canManage && ownWorkerId != null && ownWorkerId.isNotEmpty) {
      workersQuery = workersQuery.eq('id', ownWorkerId);
    }
    final workers = await workersQuery.order('name');

    var qualificationsQuery = _client
        .from('worker_qualifications')
        .select(
          'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, notes',
        )
        .eq('company_id', companyId);
    if (!canManage && ownWorkerId != null && ownWorkerId.isNotEmpty) {
      qualificationsQuery =
          qualificationsQuery.eq('worker_id', ownWorkerId);
    }
    final qualifications =
        await qualificationsQuery.order('created_at', ascending: false);

    return {
      'masters': List<Map<String, dynamic>>.from(masters),
      'workers': List<Map<String, dynamic>>.from(workers),
      'qualifications': List<Map<String, dynamic>>.from(qualifications),
    };
  }

  Future<Map<String, dynamic>> uploadCertificate({
    required String qualificationId,
    required String workerId,
    required Uint8List bytes,
    required String originalFilename,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final existingRows = await _client
        .from('worker_qualifications')
        .select('attachment_path')
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .limit(1);
    if (existingRows.isEmpty) {
      throw StateError('資格情報が見つかりません。');
    }

    final oldPath = existingRows.first['attachment_path']?.toString();
    final extension = _extensionOf(originalFilename);
    final objectName = '${DateTime.now().microsecondsSinceEpoch}$extension';
    final storagePath = '$companyId/$workerId/$qualificationId/$objectName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    try {
      final updated = await _client
          .from('worker_qualifications')
          .update({'attachment_path': storagePath})
          .eq('company_id', companyId)
          .eq('id', qualificationId)
          .select(
            'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, notes',
          )
          .single();

      if (oldPath != null && oldPath.isNotEmpty && oldPath != storagePath) {
        await _client.storage.from(_bucket).remove([oldPath]);
      }
      return Map<String, dynamic>.from(updated);
    } catch (_) {
      await _client.storage.from(_bucket).remove([storagePath]);
      rethrow;
    }
  }

  Future<String> createSignedUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 10);
  }

  Future<Map<String, dynamic>> removeCertificate({
    required String qualificationId,
    required String storagePath,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final updated = await _client
        .from('worker_qualifications')
        .update({'attachment_path': null})
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .select(
          'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, notes',
        )
        .single();
    await _client.storage.from(_bucket).remove([storagePath]);
    return Map<String, dynamic>.from(updated);
  }

  String _extensionOf(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot < 0 || lastDot == filename.length - 1) return '.jpg';
    final ext = filename.substring(lastDot).toLowerCase();
    if (ext.length > 8) return '.jpg';
    final sanitized = ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
    return sanitized.isEmpty ? '.jpg' : sanitized;
  }
}
