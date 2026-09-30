import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class QualificationMasterCandidateRepository {
  QualificationMasterCandidateRepository._(this._client);

  final SupabaseClient _client;

  static QualificationMasterCandidateRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return QualificationMasterCandidateRepository._(client);
  }

  Future<({String companyId, String role})> _membership() async {
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

  Future<({String companyId, String role})> _requireAdmin() async {
    final membership = await _membership();
    if (membership.role != 'owner' && membership.role != 'admin') {
      throw StateError('資格マスターは管理者のみ変更できます。');
    }
    return membership;
  }

  Future<Map<String, dynamic>> createMaster({
    required String name,
    List<String> aliases = const [],
  }) async {
    final membership = await _requireAdmin();
    final inserted = await _client
        .from('qualification_master')
        .insert({
          'company_id': membership.companyId,
          'name': name.trim(),
          'is_active': true,
          'is_company_custom': true,
        })
        .select('id, name')
        .single();
    final master = Map<String, dynamic>.from(inserted);
    final masterId = master['id']?.toString() ?? '';
    if (masterId.isEmpty) return master;

    final uniqueAliases = aliases
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != name.trim())
        .toSet();

    for (final alias in uniqueAliases) {
      await _insertAlias(
        companyId: membership.companyId,
        masterId: masterId,
        aliasName: alias,
      );
    }
    return master;
  }

  Future<void> addAliases({
    required String masterId,
    required Iterable<String> aliases,
  }) async {
    final membership = await _requireAdmin();
    final masters = await _client
        .from('qualification_master')
        .select('id, name')
        .eq('company_id', membership.companyId)
        .eq('id', masterId)
        .limit(1);
    if (masters.isEmpty) {
      throw StateError('資格マスターが見つかりません。');
    }
    final canonical = masters.first['name']?.toString().trim() ?? '';
    final uniqueAliases = aliases
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != canonical)
        .toSet();
    for (final alias in uniqueAliases) {
      await _insertAlias(
        companyId: membership.companyId,
        masterId: masterId,
        aliasName: alias,
      );
    }
  }

  Future<void> _insertAlias({
    required String companyId,
    required String masterId,
    required String aliasName,
  }) async {
    final existing = await _client
        .from('qualification_master_aliases')
        .select('id')
        .eq('company_id', companyId)
        .eq('qualification_master_id', masterId)
        .eq('alias_name', aliasName)
        .limit(1);
    if (existing.isNotEmpty) return;

    await _client.from('qualification_master_aliases').insert({
      'company_id': companyId,
      'qualification_master_id': masterId,
      'alias_name': aliasName,
    });
  }
}
