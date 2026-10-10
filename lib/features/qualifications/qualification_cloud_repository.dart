import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class QualificationCloudRepository {
  QualificationCloudRepository._(this._client);

  final SupabaseClient _client;

  static QualificationCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return QualificationCloudRepository._(client);
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

  Future<bool> canManageMaster() async {
    final value = await membership();
    return value.role == 'owner' || value.role == 'admin';
  }

  Future<bool> canManageWorkerQualifications() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
  }

  Future<void> _requireManageWorkerQualifications() async {
    if (!await canManageWorkerQualifications()) {
      throw StateError('資格情報を変更する権限がありません。');
    }
  }

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('SKOへのログインが必要です。');
    }
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) {
      throw StateError('会社情報が見つかりません。');
    }
    return rows.first['company_id'] as String;
  }

  Future<Map<String, dynamic>> loadAll() async {
    final companyId = await _companyId();
    final canManage = await canManageWorkerQualifications();

    String? ownWorkerId;
    if (!canManage) {
      final value = await _client.rpc('ensure_current_user_worker');
      ownWorkerId = value?.toString();
    }

    final masters = await _client
        .from('qualification_master')
        .select(
          'id, name, category, issuer, expiry_required, notes, is_active, source_name, source_reference, source_updated_at, external_source_id, is_company_custom',
        )
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
          'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at',
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

  Future<Map<String, dynamic>> insertMaster({
    required String name,
    String? category,
    String? issuer,
    bool expiryRequired = false,
    String? notes,
  }) async {
    final companyId = await _companyId();
    final inserted = await _client
        .from('qualification_master')
        .insert({
          'company_id': companyId,
          'name': name.trim(),
          'category': _nullable(category),
          'issuer': _nullable(issuer),
          'expiry_required': expiryRequired,
          'notes': _nullable(notes),
          'is_active': true,
          'is_company_custom': true,
        })
        .select(
          'id, name, category, issuer, expiry_required, notes, is_active, source_name, source_reference, source_updated_at, external_source_id, is_company_custom',
        )
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<({String workerId, String workerName})> currentWorker() async {
    final workerIdRaw = await _client.rpc('ensure_current_user_worker');
    final workerId = workerIdRaw?.toString() ?? '';
    if (workerId.isEmpty) {
      throw StateError('本人の作業員情報を確認できません。');
    }
    final row = await _client
        .from('workers')
        .select('name')
        .eq('id', workerId)
        .maybeSingle();
    final workerName = row?['name']?.toString().trim();
    return (
      workerId: workerId,
      workerName: workerName?.isNotEmpty == true ? workerName! : '本人',
    );
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Read-only preview follows existing ownership and Storage SELECT policies.
  /// Optional extra-photo data remains compatible before its migration deploys.
  static List<({String label, String path})> ownPhotoAttachments(Map row) {
    final photos = <({String label, String path})>[];
    final seen = <String>{};
    void add(Object? value, String label) {
      if (value is! String || value.trim().isEmpty || !seen.add(value)) return;
      photos.add((label: label, path: value));
    }

    add(row['attachment_path'], '表面');
    add(row['attachment_back_path'], '裏面');
    final extra = row['attachment_extra_paths'];
    if (extra is List) {
      for (var i = 0; i < extra.length; i++) {
        add(extra[i], '追加写真 ${i + 1}');
      }
    }
    return List.unmodifiable(photos);
  }

  static bool isMissingOwnPhotoColumn(PostgrestException error, String column) {
    if (error.code != '42703' && error.code != 'PGRST204') return false;
    // Exact column tokens prevent permission/network/other schema failures from
    // being hidden by a legacy retry.
    return RegExp(
      '(?<![A-Za-z0-9_])' + RegExp.escape(column) + '(?![A-Za-z0-9_])',
    ).hasMatch(error.message);
  }

  Future<List<Map<String, dynamic>>> _loadOwnPhotoRows({
    required String companyId,
    required String workerId,
    String? qualificationId,
  }) async {
    const baseFields =
        'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at';
    final optionalFields = <String>[
      'attachment_back_path',
      'attachment_extra_paths',
    ];
    while (true) {
      try {
        var query = _client
            .from('worker_qualifications')
            .select([baseFields, ...optionalFields].join(', '))
            .eq('company_id', companyId)
            .eq('worker_id', workerId);
        if (qualificationId != null) query = query.eq('id', qualificationId);
        final rows = qualificationId == null
            ? await query.order('created_at', ascending: false)
            : await query.limit(1);
        return List<Map<String, dynamic>>.from(rows);
      } on PostgrestException catch (error) {
        final missing = optionalFields
            .where((column) => isMissingOwnPhotoColumn(error, column))
            .toList();
        if (missing.isEmpty) rethrow;
        optionalFields.remove(missing.single);
      }
    }
  }

  Future<String> createOwnQualificationPhotoUrl({
    required String qualificationId,
    required String storagePath,
  }) async {
    final actor = currentUserId;
    if (actor == null) throw StateError('ログインを確認してください。');
    final worker = await currentWorker();
    if (currentUserId != actor) throw StateError('ログイン状態が変わりました。');
    final companyId = await _companyId();
    if (currentUserId != actor) throw StateError('ログイン状態が変わりました。');
    final rows = await _loadOwnPhotoRows(
      companyId: companyId,
      workerId: worker.workerId,
      qualificationId: qualificationId,
    );
    if (currentUserId != actor ||
        rows.length != 1 ||
        !ownPhotoAttachments(rows.single)
            .any((photo) => photo.path == storagePath)) {
      throw StateError('本人の資格証写真を確認できませんでした。');
    }
    final url = await _client.storage
        .from('qualification-certificates')
        .createSignedUrl(storagePath, 60 * 10);
    if (currentUserId != actor) throw StateError('ログイン状態が変わりました。');
    return url;
  }

  Future<Map<String, dynamic>> loadOwnQualificationWorkspace() async {
    final worker = await currentWorker();
    final masters = await loadActiveMasters();
    final companyId = await _companyId();
    final qualifications = await _loadOwnPhotoRows(
      companyId: companyId,
      workerId: worker.workerId,
    );

    return {
      'worker': {'id': worker.workerId, 'name': worker.workerName},
      'masters': masters,
      'qualifications': List<Map<String, dynamic>>.from(qualifications),
    };
  }

  Future<List<Map<String, dynamic>>> loadActiveMasters() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('qualification_master')
        .select('id, name, category, issuer, expiry_required, notes, is_active')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> insertOwnQualification({
    required String qualificationMasterId,
    String? certificateNumber,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? issuer,
    String? notes,
  }) async {
    final worker = await currentWorker();
    final companyId = await _companyId();
    final inserted = await _client
        .from('worker_qualifications')
        .insert({
          'company_id': companyId,
          'worker_id': worker.workerId,
          'qualification_master_id': qualificationMasterId,
          'certificate_number': _nullable(certificateNumber),
          'issued_at': _date(issuedAt),
          'expires_at': _date(expiresAt),
          'issuer': _nullable(issuer),
          'notes': _nullable(notes),
        })
        .select(
          'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at',
        )
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<Map<String, dynamic>> insertWorkerQualification({
    required String workerId,
    required String qualificationMasterId,
    String? certificateNumber,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? issuer,
    String? notes,
    String? attachmentPath,
  }) async {
    await _requireManageWorkerQualifications();
    final companyId = await _companyId();
    final inserted = await _client
        .from('worker_qualifications')
        .insert({
          'company_id': companyId,
          'worker_id': workerId,
          'qualification_master_id': qualificationMasterId,
          'certificate_number': _nullable(certificateNumber),
          'issued_at': _date(issuedAt),
          'expires_at': _date(expiresAt),
          'issuer': _nullable(issuer),
          'notes': _nullable(notes),
          'attachment_path': _nullable(attachmentPath),
        })
        .select(
          'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at',
        )
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<void> deleteWorkerQualification(String id) async {
    await _requireManageWorkerQualifications();
    await _client.from('worker_qualifications').delete().eq('id', id);
  }

  String? _date(DateTime? value) {
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
