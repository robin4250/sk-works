import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class SiteCloudRepository {
  SiteCloudRepository._(this._client);

  final SupabaseClient _client;

  static SiteCloudRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return SiteCloudRepository._(client);
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

  Future<bool> canManageSites() async {
    final value = await membership();
    return value.role == 'owner' ||
        value.role == 'admin' ||
        value.role == 'manager';
  }

  Future<bool> canCreateSites() async {
    await membership();
    return true;
  }


  Future<List<Map<String, dynamic>>> loadAll() async {
    final rows = await _client.rpc('site_directory_rows');
    if (rows is! List) return const <Map<String, dynamic>>[];

    return rows.map<Map<String, dynamic>>((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      return {
        'id': row['id'],
        'name': row['name'] ?? '',
        'customerName': row['customer_name'] ?? '',
        'status': _fromDbStatus(row['status']?.toString()),
        'address': row['address'] ?? '',
        'managerName': row['manager_name'] ?? '',
        'startDate': _displayDate(row['starts_at']?.toString()),
        'endDate': _displayDate(row['ends_at']?.toString()),
        'notes': row['notes'] ?? '',
      };
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>> insert(Map<String, dynamic> record) async {
    final customerName = record['customerName']?.toString().trim() ?? '';
    final siteName = record['name']?.toString().trim() ?? '';
    if (siteName.isEmpty) throw StateError('現場名を入力してください。');
    if (customerName.isEmpty) throw StateError('得意先を入力してください。');

    final insertedId = await _client.rpc(
      'create_basic_site_for_member',
      params: {
        'p_name': siteName,
        'p_customer_name': customerName,
        'p_address': _nullable(record['address']),
        'p_starts_at': _dbDate(record['startDate']),
        'p_ends_at': _dbDate(record['endDate']),
        'p_manager_name': _nullable(record['managerName']),
        'p_status': _toDbStatus(record['status']?.toString()),
        'p_notes': _nullable(record['notes']),
      },
    );

    return {...record, 'id': insertedId?.toString() ?? ''};
  }

  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _client.from('sites').delete().eq('id', id);
  }

  String _toDbStatus(String? value) => switch (value) {
        'active' => 'active',
        'paused' => 'paused',
        'completed' => 'completed',
        _ => 'preparation',
      };

  String _fromDbStatus(String? value) => switch (value) {
        'active' => 'active',
        'paused' => 'paused',
        'completed' => 'completed',
        _ => 'preparing',
      };

  String _displayDate(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.replaceAll('-', '/');
  }

  Object? _dbDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return text.replaceAll('/', '-');
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
