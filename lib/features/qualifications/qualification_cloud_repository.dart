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

  Future<String> _companyId() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('SK WORKSへのログインが必要です。');
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

    final masters = await _client
        .from('qualification_master')
        .select('id, name, category, issuer, expiry_required, notes')
        .eq('company_id', companyId)
        .order('name');

    final workers = await _client
        .from('workers')
        .select('id, name, affiliation, status')
        .eq('company_id', companyId)
        .order('name');

    final qualifications = await _client
        .from('worker_qualifications')
        .select(
          'id, worker_id, qualification_master_id, certificate_number, issued_at, expires_at, issuer, attachment_path, notes',
        )
        .eq('company_id', companyId)
        .order('created_at', ascending: false);

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
        })
        .select('id, name, category, issuer, expiry_required, notes')
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
