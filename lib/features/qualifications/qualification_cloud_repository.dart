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
    await membership();
    final value = await _client.rpc('current_feature_permissions');
    if (value is! Map) return false;
    final permissions = Map<String, dynamic>.from(value);
    return permissions['can_manage_people'] == true;
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
        .select('id, name, category, issuer, expiry_required, notes, is_active, source_name, source_reference, source_updated_at, external_source_id, is_company_custom')
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
          'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes',
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
        .select('id, name, category, issuer, expiry_required, notes, is_active, source_name, source_reference, source_updated_at, external_source_id, is_company_custom')
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
          'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes',
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
