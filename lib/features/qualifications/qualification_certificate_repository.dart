// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class QualificationCertificateRepository {
  QualificationCertificateRepository._(this._client);

  QualificationCertificateRepository.forTesting(this._client);

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

    if (!canManage && (ownWorkerId == null || ownWorkerId.isEmpty)) {
      return {
        'masters': List<Map<String, dynamic>>.from(masters),
        'workers': const <Map<String, dynamic>>[],
        'qualifications': const <Map<String, dynamic>>[],
      };
    }

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
          'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, attachment_back_path, attachment_extra_paths, notes',
        )
        .eq('company_id', companyId);
    if (!canManage && ownWorkerId != null && ownWorkerId.isNotEmpty) {
      qualificationsQuery = qualificationsQuery.eq('worker_id', ownWorkerId);
    }
    final qualifications = await qualificationsQuery.order(
      'created_at',
      ascending: false,
    );

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
        .eq('worker_id', workerId)
        .limit(1);
    if (existingRows.isEmpty) {
      throw StateError('資格情報が見つかりません。');
    }

    final oldPath = existingRows.first['attachment_path']?.toString();
    final extension = _extensionOf(originalFilename);
    final objectName = '${DateTime.now().microsecondsSinceEpoch}$extension';
    final storagePath = '$companyId/$workerId/$qualificationId/$objectName';

    await _client.storage
        .from(_bucket)
        .uploadBinary(
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
          .eq('worker_id', workerId)
          .filter(
            'attachment_path',
            oldPath == null ? 'is' : 'eq',
            oldPath ?? 'null',
          )
          .select(
            'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, attachment_back_path, attachment_extra_paths, notes',
          )
          .single();

      // Old objects can be referenced by company exchange snapshots.
      // Retain them until a server-side global reference check proves unused.
      return Map<String, dynamic>.from(updated);
    } catch (_) {
      // A timeout may follow a committed update. Never delete this object.
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadCertificateBack({
    required String qualificationId,
    required String workerId,
    required Uint8List bytes,
    required String originalFilename,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final existingRows = await _client
        .from('worker_qualifications')
        .select('attachment_back_path')
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('worker_id', workerId)
        .limit(1);
    if (existingRows.isEmpty) {
      throw StateError('資格情報が見つかりません。');
    }

    final oldPath = existingRows.first['attachment_back_path']?.toString();
    final extension = _extensionOf(originalFilename);
    final objectName =
        DateTime.now().microsecondsSinceEpoch.toString() + '_back' + extension;
    final storagePath =
        companyId + '/' + workerId + '/' + qualificationId + '/' + objectName;

    await _client.storage
        .from(_bucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    try {
      final updated = await _client
          .from('worker_qualifications')
          .update({'attachment_back_path': storagePath})
          .eq('company_id', companyId)
          .eq('id', qualificationId)
          .eq('worker_id', workerId)
          .filter(
            'attachment_back_path',
            oldPath == null ? 'is' : 'eq',
            oldPath ?? 'null',
          )
          .select(
            'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, attachment_back_path, attachment_extra_paths, notes',
          )
          .single();

      // Old objects can be referenced by company exchange snapshots.
      // Retain them until a server-side global reference check proves unused.
      return Map<String, dynamic>.from(updated);
    } catch (_) {
      // A timeout may follow a committed update. Never delete this object.
      rethrow;
    }
  }

  Future<Map<String, dynamic>> removeCertificateBack({
    required String qualificationId,
    required String storagePath,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final updated = await _client
        .from('worker_qualifications')
        .update({'attachment_back_path': null})
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('attachment_back_path', storagePath)
        .select(
          'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, attachment_back_path, attachment_extra_paths, notes',
        )
        .single();
    return Map<String, dynamic>.from(updated);
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
        .eq('attachment_path', storagePath)
        .select(
          'id, worker_id, qualification_master_id, certificate_number, expires_at, attachment_path, attachment_back_path, attachment_extra_paths, notes',
        )
        .single();
    return Map<String, dynamic>.from(updated);
  }

  static List<String> extraPaths(Map<String, dynamic> row) =>
      (row['attachment_extra_paths'] as List? ?? const [])
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();

  Future<Map<String, dynamic>> uploadExtraCertificate({
    required String qualificationId,
    required String workerId,
    required Uint8List bytes,
    required String originalFilename,
    String? replacingPath,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final existing = await _client
        .from('worker_qualifications')
        .select()
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('id', qualificationId)
        .single();
    final paths = extraPaths(existing);
    if (replacingPath != null && !paths.contains(replacingPath)) {
      throw StateError('写真が更新されています。再読み込みしてください。');
    }
    final path =
        '$companyId/$workerId/$qualificationId/'
        '${DateTime.now().microsecondsSinceEpoch}_extra${_extensionOf(originalFilename)}';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    if (replacingPath == null) {
      paths.add(path);
    } else {
      paths[paths.indexOf(replacingPath)] = path;
    }
    // Compare against the loaded array so another edit cannot be overwritten.
    final updated = await _client
        .from('worker_qualifications')
        .update({'attachment_extra_paths': paths})
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('id', qualificationId)
        .eq('attachment_extra_paths', existing['attachment_extra_paths'] ?? [])
        .select()
        .single();
    // Preserve old objects referenced by shared qualification snapshots.
    return Map<String, dynamic>.from(updated);
  }

  Future<Map<String, dynamic>> removeExtraCertificate({
    required String qualificationId,
    required String storagePath,
  }) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final existing = await _client
        .from('worker_qualifications')
        .select()
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .single();
    final paths = extraPaths(existing);
    if (!paths.remove(storagePath)) {
      throw StateError('写真が更新されています。再読み込みしてください。');
    }
    final updated = await _client
        .from('worker_qualifications')
        .update({'attachment_extra_paths': paths})
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('attachment_extra_paths', existing['attachment_extra_paths'] ?? [])
        .select()
        .single();
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
