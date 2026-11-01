// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'qualification_document_read_scope.dart';

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

  String? get currentUserId => _client.auth.currentUser?.id;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  Future<T> _withActor<T>(Future<T> Function(void Function()) action) async {
    final actor = currentUserId;
    if (actor == null) throw StateError('SKOへのログインが必要です。');
    var revoked = false;
    final subscription = authChanges.listen((state) {
      if (state.session?.user.id != actor) revoked = true;
    }, onError: (Object error) => revoked = true);
    void check() {
      if (revoked || currentUserId != actor) {
        throw StateError('ログイン状態が変わりました。');
      }
    }
    try {
      check();
      final result = await action(check);
      check();
      return result;
    } finally {
      await subscription.cancel();
    }
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
    final scope = await QualificationDocumentReadScope.capture(_client);
    final companyId = scope.companyId;
    final canManage = await scope.peoplePermission();
    final own = canManage ? null : await scope.ownWorker();
    final ownWorkerId = own?['id'] as String?;
    final masters = List<Map<String, dynamic>>.from(await scope.read(() => _client
        .from('qualification_master').select('id, company_id, name, issuer')
        .eq('company_id', companyId).order('name')
        .setHeader('Authorization', 'Bearer ${scope.token}')));
    if (masters.any((row) => !QualificationDocumentReadScope.uuid(row['id']) ||
        row['company_id'] != companyId) ||
        masters.map((row) => row['id']).toSet().length != masters.length) {
      throw StateError('所属会社の資格項目を確認できません。');
    }
    final List<Map<String, dynamic>> workers;
    if (canManage) {
      workers = List<Map<String, dynamic>>.from(await scope.read(() => _client
          .from('workers').select('id, company_id, name, affiliation, status')
          .eq('company_id', companyId).order('name')
          .setHeader('Authorization', 'Bearer ${scope.token}')));
      scope.validateWorkers(workers);
    } else {
      workers = [Map<String, dynamic>.from(own!)..remove('user_id')];
    }
    Future<List<Map<String, dynamic>>> readQualifications({required bool extras}) async {
      final rows = await scope.read(() {
        var query = _client.from('worker_qualifications').select(
            'id, company_id, worker_id, qualification_master_id, certificate_number, expires_at, '
            'attachment_path, attachment_back_path, '
            '${extras ? 'attachment_extra_paths, ' : ''}notes')
            .eq('company_id', companyId);
        if (!canManage) query = query.eq('worker_id', ownWorkerId!);
        return query.order('created_at', ascending: false)
            .setHeader('Authorization', 'Bearer ${scope.token}');
      });
      return List<Map<String, dynamic>>.from(rows);
    }
    var supportsExtraPhotos = true;
    List<Map<String, dynamic>> qualifications;
    try {
      qualifications = await readQualifications(extras: true);
    } on PostgrestException catch (error) {
      scope.check();
      if (!QualificationDocumentReadScope.missingPhotoColumn(error, 'attachment_extra_paths')) rethrow;
      supportsExtraPhotos = false;
      qualifications = await readQualifications(extras: false);
    }
    scope.validateQualifications(qualifications, ownWorkerId: ownWorkerId);
    final workerIds = workers.map((row) => row['id']).toSet();
    if (qualifications.any((row) => !workerIds.contains(row['worker_id']))) {
      throw StateError('資格書類の対象社員を確認できません。');
    }
    await scope.verify(worker: own, peoplePermission: canManage);
    for (final row in [...masters, ...workers, ...qualifications]) { row.remove('company_id'); }
    return {'masters': masters, 'workers': workers, 'qualifications': qualifications,
      'supports_extra_photos': supportsExtraPhotos};
  }

  Future<Map<String, dynamic>> uploadCertificate({
    required String qualificationId,
    required String workerId,
    required Uint8List bytes,
    required String originalFilename,
  }) => _withActor((check) async {
    await _requireManagePeople();
    check();
    final companyId = await _companyId();
    check();
    final existingRows = await _client
        .from('worker_qualifications')
        .select('attachment_path')
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('worker_id', workerId)
        .limit(1);
    check();
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
    check();

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
          .select()
          .single();
    check();

      // Old objects can be referenced by company exchange snapshots.
      // Retain them until a server-side global reference check proves unused.
      return Map<String, dynamic>.from(updated);
    } catch (_) {
      // A timeout may follow a committed update. Never delete this object.
      rethrow;
    }
  });

  Future<Map<String, dynamic>> uploadCertificateBack({
    required String qualificationId,
    required String workerId,
    required Uint8List bytes,
    required String originalFilename,
  }) => _withActor((check) async {
    await _requireManagePeople();
    check();
    final companyId = await _companyId();
    check();
    final existingRows = await _client
        .from('worker_qualifications')
        .select('attachment_back_path')
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('worker_id', workerId)
        .limit(1);
    check();
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
    check();

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
          .select()
          .single();
    check();

      // Old objects can be referenced by company exchange snapshots.
      // Retain them until a server-side global reference check proves unused.
      return Map<String, dynamic>.from(updated);
    } catch (_) {
      // A timeout may follow a committed update. Never delete this object.
      rethrow;
    }
  });

  Future<Map<String, dynamic>> removeCertificateBack({
    required String qualificationId,
    required String storagePath,
  }) => _withActor((check) async {
    await _requireManagePeople();
    check();
    final companyId = await _companyId();
    check();
    final updated = await _client
        .from('worker_qualifications')
        .update({'attachment_back_path': null})
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('attachment_back_path', storagePath)
        .select()
        .single();
    check();
    return Map<String, dynamic>.from(updated);
  });

  Future<String> createSignedUrl(String storagePath) async {
    final scope = await QualificationDocumentReadScope.capture(_client);
    final canManage = await scope.peoplePermission();
    final own = canManage ? null : await scope.ownWorker();
    final rows = await scope.photoRows(workerId: own?['id'] as String?);
    final matches = rows.where((row) => QualificationDocumentReadScope.photoPaths(row)
        .contains(storagePath)).toList();
    if (matches.length != 1) throw StateError('保存済み資格証写真を一意に確認できません。');
    final row = matches.single;
    final target = canManage ? await scope.visibleWorker(row['worker_id'] as String) : own!;
    scope.validatePhotoPath(storagePath, row);
    await scope.verify(worker: own, peoplePermission: canManage);
    final url = await scope.signPhoto(storagePath, row);
    final fresh = await scope.photoRows(workerId: row['worker_id'] as String,
        qualificationId: row['id'] as String);
    if (fresh.length != 1) throw StateError('資格証写真が変更されました。');
    scope.validatePhotoPath(storagePath, fresh.single);
    if (canManage && (await scope.visibleWorker(row['worker_id'] as String))['status'] != target['status']) {
      throw StateError('対象社員の在籍状態が変更されました。');
    }
    await scope.verify(worker: own, peoplePermission: canManage);
    return url;
  }

  Future<Map<String, dynamic>> removeCertificate({
    required String qualificationId,
    required String storagePath,
  }) => _withActor((check) async {
    await _requireManagePeople();
    check();
    final companyId = await _companyId();
    check();
    final updated = await _client
        .from('worker_qualifications')
        .update({'attachment_path': null})
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .eq('attachment_path', storagePath)
        .select()
        .single();
    check();
    return Map<String, dynamic>.from(updated);
  });

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
  }) => _withActor((check) async {
    await _requireManagePeople();
    check();
    final companyId = await _companyId();
    check();
    final existing = await _client
        .from('worker_qualifications')
        .select()
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('id', qualificationId)
        .single();
    check();
    if (!existing.containsKey('attachment_extra_paths')) {
      throw StateError('追加写真の保存は準備中です。表面・裏面は引き続き確認できます。');
    }
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
    check();
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
    check();
    // Preserve old objects referenced by shared qualification snapshots.
    return Map<String, dynamic>.from(updated);
  });

  Future<Map<String, dynamic>> removeExtraCertificate({
    required String qualificationId,
    required String storagePath,
  }) => _withActor((check) async {
    await _requireManagePeople();
    check();
    final companyId = await _companyId();
    check();
    final existing = await _client
        .from('worker_qualifications')
        .select()
        .eq('company_id', companyId)
        .eq('id', qualificationId)
        .single();
    check();
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
    check();
    return Map<String, dynamic>.from(updated);
  });

  String _extensionOf(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot < 0 || lastDot == filename.length - 1) return '.jpg';
    final ext = filename.substring(lastDot).toLowerCase();
    if (ext.length > 8) return '.jpg';
    final sanitized = ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
    return sanitized.isEmpty ? '.jpg' : sanitized;
  }
}

