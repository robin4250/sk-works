// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class CompanySubmittedDocumentRepository {
  CompanySubmittedDocumentRepository._(this._client);

  final SupabaseClient _client;
  static const bucket = 'company-required-documents';

  static CompanySubmittedDocumentRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return CompanySubmittedDocumentRepository._(client);
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

  Future<void> requireAdmin() async {
    final value = await membership();
    if (value.role != 'owner' && value.role != 'admin') {
      throw StateError('会社提出書類は管理者のみ操作できます。');
    }
  }
  Future<Map<String, dynamic>> loadCompanyData() async {
    await requireAdmin();
    final value = await _client.rpc('company_data_state');
    if (value is! Map) {
      throw StateError('会社データを読み込めませんでした。');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<bool> loadCompanySealEnabled() async {
    await requireAdmin();
    final value = await _client.rpc('company_seal_settings');
    if (value is! Map || value['company_seal_enabled'] is! bool) {
      throw StateError('会社角印の設定を読み込めませんでした。');
    }
    return value['company_seal_enabled'] as bool;
  }

  Future<bool> saveCompanySealEnabled(bool enabled) async {
    await requireAdmin();
    final value = await _client.rpc(
      'save_company_seal_settings',
      params: {'p_enabled': enabled},
    );
    if (value is! Map || value['company_seal_enabled'] is! bool) {
      throw StateError('会社角印の設定を保存できませんでした。');
    }
    return value['company_seal_enabled'] as bool;
  }

  Future<void> saveCompanyData({
    required String name,
    required String address,
    required String corporateNumber,
    required String phone,
    required String fax,
    required String email,
    required String bankName,
    required String bankBranch,
    required String bankAccountNumber,
    required String bankAccountHolder,
  }) async {
    await requireAdmin();
    await _client.rpc(
      'save_company_data',
      params: {
        'p_name': name.trim(),
        'p_address': address.trim(),
        'p_corporate_number': corporateNumber.trim(),
        'p_phone': phone.trim(),
        'p_fax': fax.trim(),
        'p_email': email.trim(),
        'p_bank_name': bankName.trim(),
        'p_bank_branch': bankBranch.trim(),
        'p_bank_account_number': bankAccountNumber.trim(),
        'p_bank_account_holder': bankAccountHolder.trim(),
      },
    );
  }


  Future<List<Map<String, dynamic>>> listDocuments() async {
    final value = await membership();
    final rows = await _client
        .from('company_required_documents')
        .select(
          'id, name, scope, upstream_name, is_active, expiry_required, expires_at, attachment_path, notes, status, original_verified, created_at, updated_at',
        )
        .eq('company_id', value.companyId)
        .eq('is_active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createDocument({
    required String name,
    DateTime? expiresAt,
    String notes = '',
  }) async {
    await requireAdmin();
    final value = await membership();
    final inserted = await _client
        .from('company_required_documents')
        .insert({
          'company_id': value.companyId,
          'name': name.trim(),
          'scope': 'upstream',
          'upstream_name': '',
          'is_active': true,
          'expiry_required': expiresAt != null,
          'expires_at': _date(expiresAt),
          'notes': notes.trim(),
          'status': 'missing',
          'original_verified': false,
        })
        .select(
          'id, name, scope, upstream_name, is_active, expiry_required, expires_at, attachment_path, notes, status, original_verified, created_at, updated_at',
        )
        .single();
    return Map<String, dynamic>.from(inserted);
  }

  Future<Map<String, dynamic>> updateMetadata({
    required String id,
    required String name,
    DateTime? expiresAt,
    String notes = '',
  }) async {
    await requireAdmin();
    final value = await membership();
    final updated = await _client
        .from('company_required_documents')
        .update({
          'name': name.trim(),
          'expiry_required': expiresAt != null,
          'expires_at': _date(expiresAt),
          'notes': notes.trim(),
        })
        .eq('company_id', value.companyId)
        .eq('id', id)
        .select(
          'id, name, scope, upstream_name, is_active, expiry_required, expires_at, attachment_path, notes, status, original_verified, created_at, updated_at',
        )
        .single();
    return Map<String, dynamic>.from(updated);
  }

  Future<Map<String, dynamic>> upload({
    required String id,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    await requireAdmin();
    final value = await membership();
    final rows = await _client
        .from('company_required_documents')
        .select('attachment_path')
        .eq('company_id', value.companyId)
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社提出書類が見つかりません。');
    final oldPath = rows.first['attachment_path']?.toString();
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = value.companyId +
        '/' +
        id +
        '/' +
        DateTime.now().microsecondsSinceEpoch.toString() +
        '_' +
        safeName;

    await _client.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );

    try {
      final updated = await _client
          .from('company_required_documents')
          .update({
            'attachment_path': path,
            'status': 'submitted',
          })
          .eq('company_id', value.companyId)
          .eq('id', id)
          .select(
            'id, name, scope, upstream_name, is_active, expiry_required, expires_at, attachment_path, notes, status, original_verified, created_at, updated_at',
          )
          .single();
      if (oldPath != null && oldPath.isNotEmpty && oldPath != path) {
        await _client.storage.from(bucket).remove([oldPath]);
      }
      return Map<String, dynamic>.from(updated);
    } catch (_) {
      await _client.storage.from(bucket).remove([path]);
      rethrow;
    }
  }

  Future<String> createSignedUrl(String path) {
    return _client.storage.from(bucket).createSignedUrl(path, 60 * 10);
  }

  Future<void> archive(String id) async {
    await requireAdmin();
    final value = await membership();
    await _client
        .from('company_required_documents')
        .update({'is_active': false})
        .eq('company_id', value.companyId)
        .eq('id', id);
  }

  String? _date(DateTime? value) {
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return value.year.toString() + '-' + month + '-' + day;
  }
}
