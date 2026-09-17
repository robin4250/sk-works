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

  Future<List<Map<String, dynamic>>> loadAll() async {
    final companyId = await _companyId();
    final companies = await _client
        .from('partner_companies')
        .select('id, name, phone, email, trade_role, notes, status')
        .eq('company_id', companyId)
        .order('name');
    final companyNames = <String, String>{
      for (final row in companies)
        row['id'] as String: row['name']?.toString() ?? '',
    };

    final workers = await _client
        .from('workers')
        .select('id, affiliation, partner_company_id, name, phone, email, role, notes, status')
        .eq('company_id', companyId)
        .order('name');

    final records = <Map<String, dynamic>>[];
    for (final row in companies) {
      records.add({
        'id': row['id'],
        'kind': 'partnerCompany',
        'name': row['name'] ?? '',
        'companyName': '',
        'phone': row['phone'] ?? '',
        'email': row['email'] ?? '',
        'role': row['trade_role'] ?? '',
        'notes': row['notes'] ?? '',
        'active': (row['status'] ?? 'active') == 'active',
      });
    }
    for (final row in workers) {
      final affiliation = row['affiliation']?.toString() ?? 'employee';
      final partnerCompanyId = row['partner_company_id'] as String?;
      records.add({
        'id': row['id'],
        'kind': affiliation == 'employee' ? 'employee' : 'partnerWorker',
        'name': row['name'] ?? '',
        'companyName': partnerCompanyId == null ? '' : companyNames[partnerCompanyId] ?? '',
        'phone': row['phone'] ?? '',
        'email': row['email'] ?? '',
        'role': row['role'] ?? '',
        'notes': row['notes'] ?? '',
        'active': (row['status'] ?? 'active') == 'active',
      });
    }
    return records;
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> record) async {
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
