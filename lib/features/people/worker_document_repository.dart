import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class WorkerDocumentRepository {
  WorkerDocumentRepository._(this._client);

  final SupabaseClient _client;
  static const _bucket = 'worker-documents';

  static WorkerDocumentRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return WorkerDocumentRepository._(client);
  }

  static const defaultRequirements = <Map<String, Object>>[
    {'name': '履歴書', 'scope': 'internal', 'expiry': false},
    {'name': '住民票', 'scope': 'internal', 'expiry': false},
    {'name': 'マイナンバーカード', 'scope': 'internal', 'expiry': true},
    {'name': '身元保証書', 'scope': 'internal', 'expiry': false},
    {'name': '社員登録票', 'scope': 'internal', 'expiry': false},
    {'name': '通勤届', 'scope': 'internal', 'expiry': false},
    {'name': '賃金の口座振込同意書', 'scope': 'internal', 'expiry': false},
    {'name': '入社連絡票', 'scope': 'internal', 'expiry': false},
    {'name': '年金手帳', 'scope': 'internal', 'expiry': false},
    {'name': '雇用保険被保険者証', 'scope': 'internal', 'expiry': false},
    {'name': '就業規則同意書', 'scope': 'internal', 'expiry': false},
    {'name': '未成年就業同意書', 'scope': 'internal', 'expiry': false},
    {'name': '運転免許証', 'scope': 'internal', 'expiry': true},
    {'name': '資格証', 'scope': 'upstream', 'expiry': true},
    {'name': '健康診断書', 'scope': 'upstream', 'expiry': true},
    {'name': '雇用契約書', 'scope': 'internal', 'expiry': false},
    {'name': '誓約書', 'scope': 'internal', 'expiry': false},
    {'name': '銀行口座情報', 'scope': 'internal', 'expiry': false},
    {'name': '自由項目1', 'scope': 'internal', 'expiry': false},
    {'name': '自由項目2', 'scope': 'internal', 'expiry': false},
  ];

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

  Future<bool> canManageRequirements() async {
    final value = await membership();
    return value.role == 'owner' || value.role == 'admin';
  }

  Future<bool> canManageStatuses() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
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

  Future<Map<String, List<Map<String, dynamic>>>> loadAll() async {
    final companyId = await _companyId();
    final workers = await _client
        .from('workers')
        .select('id, name, affiliation, status')
        .eq('company_id', companyId)
        .eq('status', 'active')
        .order('name');
    final requirements = await _client
        .from('document_requirements')
        .select('id, name, scope, is_required, expiry_required, renewal_reminder_days, is_active, sort_order')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('sort_order')
        .order('name');
    final statuses = await _client
        .from('worker_document_statuses')
        .select('id, worker_id, requirement_id, status, expires_at, original_verified, attachment_path, notes, updated_at')
        .eq('company_id', companyId);

    return {
      'workers': List<Map<String, dynamic>>.from(workers),
      'requirements': List<Map<String, dynamic>>.from(requirements),
      'statuses': List<Map<String, dynamic>>.from(statuses),
    };
  }

  Future<void> addDefaultRequirements() async {
    final companyId = await _companyId();
    final existingRows = await _client
        .from('document_requirements')
        .select('name, scope')
        .eq('company_id', companyId);
    final existing = existingRows
        .map((row) => '${row['scope']}::${row['name']}')
        .toSet();

    var order = 0;
    for (final item in defaultRequirements) {
      final name = item['name']! as String;
      final scope = item['scope']! as String;
      final key = '$scope::$name';
      if (existing.contains(key)) {
        order += 10;
        continue;
      }
      await _client.from('document_requirements').insert({
        'company_id': companyId,
        'name': name,
        'scope': scope,
        'is_required': true,
        'expiry_required': item['expiry']! as bool,
        'renewal_reminder_days': 30,
        'sort_order': order,
      });
      order += 10;
    }
  }

  Future<void> addRequirement({
    required String name,
    required String scope,
    required bool isRequired,
    required bool expiryRequired,
  }) async {
    final companyId = await _companyId();
    await _client.from('document_requirements').insert({
      'company_id': companyId,
      'name': name,
      'scope': scope,
      'is_required': isRequired,
      'expiry_required': expiryRequired,
      'renewal_reminder_days': 30,
    });
  }

  Future<Map<String, dynamic>> uploadAttachment({
    required String statusId,
    required String workerId,
    required String requirementId,
    required Uint8List bytes,
    required String originalFilename,
  }) async {
    final companyId = await _companyId();
    final rows = await _client
        .from('worker_document_statuses')
        .select('id, attachment_path')
        .eq('company_id', companyId)
        .eq('id', statusId)
        .limit(1);
    if (rows.isEmpty) throw StateError('書類情報が見つかりません。');

    final oldPath = rows.first['attachment_path']?.toString();
    final extension = _extensionOf(originalFilename);
    final objectName = '${DateTime.now().microsecondsSinceEpoch}$extension';
    final storagePath =
        '$companyId/$workerId/$requirementId/$statusId/$objectName';

    await _client.storage.from(_bucket).uploadBinary(
      storagePath,
      bytes,
      fileOptions: const FileOptions(upsert: false),
    );

    try {
      final updated = await _client
          .from('worker_document_statuses')
          .update({
            'attachment_path': storagePath,
            'updated_by': _client.auth.currentUser?.id,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('company_id', companyId)
          .eq('id', statusId)
          .select(
            'id, worker_id, requirement_id, status, expires_at, original_verified, attachment_path, notes, updated_at',
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

  Future<String> createSignedAttachmentUrl(String storagePath) {
    return _client.storage.from(_bucket).createSignedUrl(storagePath, 60 * 10);
  }

  Future<Map<String, dynamic>> removeAttachment({
    required String statusId,
    required String storagePath,
  }) async {
    final companyId = await _companyId();
    final updated = await _client
        .from('worker_document_statuses')
        .update({
          'attachment_path': null,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('company_id', companyId)
        .eq('id', statusId)
        .select(
          'id, worker_id, requirement_id, status, expires_at, original_verified, attachment_path, notes, updated_at',
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

  Future<void> updateStatus({
    required String workerId,
    required String requirementId,
    required String status,
    DateTime? expiresAt,
    required bool originalVerified,
    required String notes,
  }) async {
    final companyId = await _companyId();
    final existing = await _client
        .from('worker_document_statuses')
        .select('id')
        .eq('worker_id', workerId)
        .eq('requirement_id', requirementId)
        .limit(1);
    final payload = {
      'company_id': companyId,
      'worker_id': workerId,
      'requirement_id': requirementId,
      'status': status,
      'expires_at': expiresAt?.toIso8601String().split('T').first,
      'original_verified': originalVerified,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (existing.isEmpty) {
      await _client.from('worker_document_statuses').insert(payload);
    } else {
      await _client
          .from('worker_document_statuses')
          .update(payload)
          .eq('id', existing.first['id']);
    }
  }
}
