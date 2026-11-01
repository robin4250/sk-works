import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import '../auth/app_auth_mutation_gateway.dart';
import 'qualification_document_read_scope.dart';

class QualificationCloudRepository {
  QualificationCloudRepository._(this._client);
  QualificationCloudRepository.forTesting(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get attachmentAuthChanges => _client.auth.onAuthStateChange;
  Future<bool Function()> captureAttachmentReadScope() async {
    final session = _client.auth.currentSession;
    final actor = _client.auth.currentUser?.id;
    final gateway = AppAuthMutationGateway.forClient(_client);
    final epoch = await gateway.externalFlowAdmission();
    if (session == null || actor == null || session.isExpired || epoch == null ||
        !identical(session, _client.auth.currentSession)) { throw StateError('Attachment session changed'); }
    return () => !session.isExpired && identical(session, _client.auth.currentSession) &&
      _client.auth.currentUser?.id == actor && gateway.isExternalFlowCurrent(epoch);
  }

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
    final scope = await QualificationDocumentReadScope.capture(_client);
    final companyId = scope.companyId;
    final canManage = const ['owner', 'admin', 'manager'].contains(scope.role);
    final own = canManage ? null : await scope.ownWorker();
    final ownWorkerId = own?['id'] as String?;
    final masters = List<Map<String, dynamic>>.from(await scope.read(() => _client
        .from('qualification_master')
        .select('id, company_id, name, category, issuer, expiry_required, notes, is_active, source_name, source_reference, source_updated_at, external_source_id, is_company_custom')
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
    const baseFields =
        'id, company_id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at';
    final optionalFields = <String>{'attachment_back_path', 'attachment_extra_paths'};
    late List<Map<String, dynamic>> qualifications;
    for (;;) {
      try {
        qualifications = List<Map<String, dynamic>>.from(await scope.read(() {
          var query = _client.from('worker_qualifications')
              .select([baseFields, ...optionalFields].join(', '))
              .eq('company_id', companyId);
          if (!canManage) query = query.eq('worker_id', ownWorkerId!);
          return query.order('created_at', ascending: false)
              .setHeader('Authorization', 'Bearer ${scope.token}');
        }));
        break;
      } on PostgrestException catch (error) {
        scope.check();
        final missing = optionalFields.where(
            (column) => isMissingOwnPhotoColumn(error, column)).toList();
        if (missing.length != 1) rethrow;
        optionalFields.remove(missing.single);
      }
    }
    scope.validateQualifications(qualifications, ownWorkerId: ownWorkerId);
    final workerIds = workers.map((row) => row['id']).toSet();
    if (qualifications.any((row) => !workerIds.contains(row['worker_id']))) {
      throw StateError('資格書類の対象社員を確認できません。');
    }
    await scope.verify(worker: own);
    for (final row in masters) { row.remove('company_id'); }
    return {'masters': masters, 'workers': workers, 'qualifications': qualifications};
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

  Future<void> updateMasterCategory(String masterId, String category) async {
    if (!await canManageWorkerQualifications()) throw StateError('資格区分を変更する権限がありません。');
    const allowed = {'国家資格', '技能講習', '実技講習', '安全教育', '特別教育'};
    if (!allowed.contains(category)) throw ArgumentError('資格区分が正しくありません。');
    final companyId = await _companyId();
    final updated = await _client.from('qualification_master')
        .update({'category': category}).eq('company_id', companyId)
        .eq('id', masterId).select('id');
    if (updated.length != 1) throw StateError('資格区分を更新できませんでした。');
  }

  // No client deletion until the server reference-preservation guard has been
  // installed and independently verified. Never infer it from a UI flag.
  Future<void> deleteMaster(String masterId) async {
    throw StateError('資格マスターの削除は準備中です。');
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
    return RegExp('(?<![A-Za-z0-9_])${RegExp.escape(column)}(?![A-Za-z0-9_])')
        .hasMatch(error.message);
  }

  Future<List<Map<String, dynamic>>> _loadOwnPhotoRows({
    required String companyId,
    required String workerId,
    String? qualificationId,
  }) async {
    const baseFields =
        'id, company_id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at';
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
    final scope = await QualificationDocumentReadScope.capture(_client);
    final worker = await scope.ownWorker();
    final rows = await scope.photoRows(workerId: worker['id'] as String,
        qualificationId: qualificationId);
    if (rows.length != 1 ||
        !ownPhotoAttachments(rows.single).any((photo) => photo.path == storagePath)) {
      throw StateError('本人の資格証写真を確認できませんでした。');
    }
    scope.validatePhotoPath(storagePath, rows.single);
    await scope.verify(worker: worker);
    final url = await scope.signPhoto(storagePath, rows.single);
    final fresh = await scope.photoRows(workerId: worker['id'] as String,
        qualificationId: qualificationId);
    if (fresh.length != 1) throw StateError('資格証写真が変更されました。');
    scope.validatePhotoPath(storagePath, fresh.single);
    await scope.verify(worker: worker);
    return url;
  }

  Future<Map<String, dynamic>> loadOwnQualificationWorkspace() async {
    final workerId = (await _client.rpc('ensure_current_user_worker'))?.toString() ?? '';
    if (workerId.isEmpty) { throw StateError('本人の作業員情報を確認できません。'); }
    final companyId = await _companyId();
    final worker = await _client.from('workers').select('id, company_id, name')
        .eq('id', workerId).eq('company_id', companyId).maybeSingle();
    if (worker == null || worker['id'] != workerId || worker['company_id'] != companyId) {
      throw StateError('本人の所属会社を確認できません。');
    }
    // One captured company scopes the worker, master and registration reads.
    final masters = await _loadActiveMastersForCompany(companyId);
    final qualifications = await _loadOwnPhotoRows(companyId: companyId, workerId: workerId);
    return {
      'worker': {'id': workerId, 'company_id': companyId, 'name': worker['name']},
      'masters': masters,
      'qualifications': List<Map<String, dynamic>>.from(qualifications),
    };
  }

  Future<List<Map<String, dynamic>>> loadActiveMasters() async =>
      _loadActiveMastersForCompany(await _companyId());

  Future<List<Map<String, dynamic>>> _loadActiveMastersForCompany(String companyId) async {
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
          'id, company_id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at',
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
          'id, company_id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes, created_at, updated_at',
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


