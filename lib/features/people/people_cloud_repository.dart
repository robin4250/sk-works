import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class PeopleCloudRepository {
  PeopleCloudRepository._(this._client);

  final SupabaseClient _client;

  static PeopleCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return PeopleCloudRepository._(client);
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

  Future<bool> canManagePeople() async {
    await membership();
    final value = await _client.rpc('current_feature_permissions');
    if (value is! Map) return false;
    final permissions = Map<String, dynamic>.from(value);
    return permissions['can_manage_people'] == true;
  }

  Future<void> _requireManagePeople() async {
    if (!await canManagePeople()) {
      throw StateError('人員管理を変更する権限がありません。');
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

  Future<List<Map<String, dynamic>>> loadAll() async {
    await _requireManagePeople();
    final rows = await _client.rpc('people_management_records');
    if (rows is! List) return const <Map<String, dynamic>>[];

    return rows.map<Map<String, dynamic>>((row) {
      final value = Map<String, dynamic>.from(row as Map);
      return {
        'id': value['id'],
        'kind': value['kind'],
        'name': value['name'] ?? '',
        'companyName': value['company_name'] ?? '',
        'phone': value['phone'] ?? '',
        'email': value['email'] ?? '',
        'role': value['role'] ?? '',
        'notes': value['notes'] ?? '',
        'active': value['active'] == true,
      };
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> record) async {
    await _requireManagePeople();
    final companyId = await _companyId();
    final kind = record['kind']?.toString() ?? 'employee';
    if (kind == 'partnerCompany') {
      final inserted = await _client
          .from('partner_companies')
          .insert({
            'company_id': companyId,
            'name': record['name'],
            'phone': _nullable(record['phone']),
            'email': _nullable(record['email']),
            'trade_role': _nullable(record['role']),
            'notes': _nullable(record['notes']),
            'status': record['active'] == false ? 'inactive' : 'active',
          })
          .select('id')
          .single();
      return {...record, 'id': inserted['id']};
    }

    String? partnerCompanyId;
    if (kind == 'partnerWorker') {
      final companyName = record['companyName']?.toString().trim() ?? '';
      if (companyName.isEmpty) {
        throw StateError('協力会社作業員は所属会社を入力してください。');
      }
      final existing = await _client
          .from('partner_companies')
          .select('id')
          .eq('company_id', companyId)
          .eq('name', companyName)
          .limit(1);
      if (existing.isNotEmpty) {
        partnerCompanyId = existing.first['id'] as String;
      } else {
        final created = await _client
            .from('partner_companies')
            .insert({
              'company_id': companyId,
              'name': companyName,
              'status': 'active',
            })
            .select('id')
            .single();
        partnerCompanyId = created['id'] as String;
      }
    }

    final inserted = await _client
        .from('workers')
        .insert({
          'company_id': companyId,
          'affiliation': kind == 'employee' ? 'employee' : 'partner_company',
          'partner_company_id': partnerCompanyId,
          'name': record['name'],
          'phone': _nullable(record['phone']),
          'email': _nullable(record['email']),
          'role': _nullable(record['role']),
          'notes': _nullable(record['notes']),
          'status': record['active'] == false ? 'inactive' : 'active',
        })
        .select('id')
        .single();
    return {...record, 'id': inserted['id']};
  }

  Future<void> delete(Map<String, dynamic> record) async {
    await _requireManagePeople();
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    final kind = record['kind']?.toString() ?? 'employee';
    final table = kind == 'partnerCompany' ? 'partner_companies' : 'workers';
    await _client.from(table).delete().eq('id', id);
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
