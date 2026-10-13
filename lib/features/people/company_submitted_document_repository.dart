// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class CompanySubmittedDocumentRepository {
  CompanySubmittedDocumentRepository._(this._client);

  CompanySubmittedDocumentRepository.forTesting(this._client);

  final SupabaseClient _client;
  static const bucket = 'company-required-documents';
  bool _supportsPhotoSets = true;
  bool get supportsPhotoSets => _supportsPhotoSets;
  static const _allFields =
      'id, name, scope, upstream_name, is_active, expiry_required, expires_at, attachment_path, attachment_paths, notes, status, original_verified, created_at, updated_at';
  String get _fields => _supportsPhotoSets
      ? _allFields
      : _allFields.replaceAll('attachment_paths, ', '');

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
    try {
      final rows = await _client
          .from('company_required_documents')
          .select(_allFields)
          .eq('company_id', value.companyId)
          .eq('is_active', true)
          .order('name');
      _supportsPhotoSets = true;
      return List<Map<String, dynamic>>.from(rows);
    } on PostgrestException catch (error) {
      final missingPhotoColumn =
          (error.code == '42703' || error.code == 'PGRST204') &&
          '${error.message} ${error.details}'.contains('attachment_paths');
      if (!missingPhotoColumn) rethrow;
      _supportsPhotoSets = false;
      final rows = await _client
          .from('company_required_documents')
          .select(_fields)
          .eq('company_id', value.companyId)
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(rows);
    }
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
        .select(_fields)
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
        .select(_fields)
        .single();
    return Map<String, dynamic>.from(updated);
  }

  Future<Map<String, dynamic>> upload({
    required String id,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    return savePhotos(
      id: id,
      retainedPaths: const [],
      legacySingleReplacement: true,
      files: [(bytes: bytes, filename: filename, contentType: contentType)],
    );
  }

  static List<String> attachmentPaths(Map<String, dynamic> row) {
    final values = row['attachment_paths'];
    if (values is List && values.isNotEmpty) {
      return values
          .map((v) => v.toString())
          .where((v) => v.isNotEmpty)
          .toList();
    }
    final legacy = row['attachment_path']?.toString() ?? '';
    return legacy.isEmpty ? [] : [legacy];
  }

  Future<Map<String, dynamic>> savePhotos({
    required String id,
    required List<String> retainedPaths,
    List<String>? expectedPaths,
    List<int>? insertionIndices,
    bool legacySingleReplacement = false,
    required List<({Uint8List bytes, String filename, String contentType})>
    files,
  }) async {
    if (!_supportsPhotoSets &&
        (!legacySingleReplacement ||
            files.length != 1 ||
            retainedPaths.isNotEmpty)) {
      throw StateError('複数写真の保存機能は準備中です。登録済み書類は引き続き確認できます。');
    }
    await requireAdmin();
    final value = await membership();
    final current = await _client
        .from('company_required_documents')
        .select(
          _supportsPhotoSets
              ? 'attachment_path, attachment_paths, updated_at'
              : 'attachment_path, updated_at',
        )
        .eq('company_id', value.companyId)
        .eq('id', id)
        .single();
    final oldPaths = attachmentPaths(current);
    if (expectedPaths != null &&
        (expectedPaths.length != oldPaths.length ||
            List.generate(
              oldPaths.length,
              (i) => oldPaths[i] == expectedPaths[i],
            ).contains(false))) {
      throw StateError('他の操作で写真が変更されました。再読み込みしてください。');
    }
    if (retainedPaths.any((path) => !oldPaths.contains(path)) ||
        retainedPaths.toSet().length != retainedPaths.length) {
      throw StateError('登録済み写真を確認できません。再読み込みしてください。');
    }
    if (insertionIndices != null &&
        (insertionIndices.length != files.length ||
            List.generate(
              files.length,
              (i) =>
                  insertionIndices[i] >= 0 &&
                  insertionIndices[i] <= retainedPaths.length + i &&
                  (i == 0 || insertionIndices[i] > insertionIndices[i - 1]),
            ).contains(false))) {
      throw StateError('写真の順序を確認できません。');
    }
    final paths = [...retainedPaths];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (file.bytes.isEmpty) throw StateError('空の写真は保存できません。');
      final safeName = file.filename.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final path =
          '${value.companyId}/$id/${DateTime.now().microsecondsSinceEpoch}_${i}_$safeName';
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(
              contentType: file.contentType,
              upsert: false,
            ),
          );
      paths.insert(insertionIndices?[i] ?? paths.length, path);
    }
    // Compare-and-set prevents a stale editor from replacing another saved set.
    var query = _client
        .from('company_required_documents')
        .update({
          'attachment_path': paths.isEmpty ? null : paths.first,
          if (_supportsPhotoSets) 'attachment_paths': paths,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'status': paths.isEmpty ? 'missing' : 'submitted',
        })
        .eq('company_id', value.companyId)
        .eq('id', id);
    if (current['updated_at'] != null) {
      query = query.eq('updated_at', current['updated_at']);
    }
    final updated = await query.select().single();
    final saved = attachmentPaths(updated);
    if (saved.length != paths.length ||
        List.generate(
          paths.length,
          (i) => saved[i] == paths[i],
        ).contains(false)) {
      throw StateError('写真の保存結果を確認できません。再読み込みしてください。');
    }
    // Never remove uploaded objects after an ambiguous network response.
    // Historical / company-exchange snapshots can still reference old objects;
    // physical cleanup requires server-side reference checks and a backup.
    return Map<String, dynamic>.from(updated);
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
