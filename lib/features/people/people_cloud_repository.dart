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

  Future<String> companyName() async {
    final member = await membership();
    final row = await _client
        .from('companies')
        .select('name')
        .eq('id', member.companyId)
        .maybeSingle();
    return row?['name']?.toString() ?? '';
  }

  Future<bool> canManagePeople() async {
    final member = await membership();
    return member.role == 'owner' ||
        member.role == 'admin' ||
        member.role == 'manager';
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

    final personnelRaw = await _client.rpc('employee_personnel_rows');
    final personnelRows = personnelRaw is List
        ? personnelRaw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final personnelByWorker = <String, Map<String, dynamic>>{
      for (final row in personnelRows)
        if ((row['worker_id']?.toString() ?? '').isNotEmpty)
          row['worker_id'].toString(): row,
    };

    final companyId = await _companyId();
    final workerDates = await _client
        .from('workers')
        .select('id,created_at,updated_at')
        .eq('company_id', companyId);
    final partnerDates = await _client
        .from('partner_companies')
        .select('id,created_at,updated_at')
        .eq('company_id', companyId);
    final datesById = <String, Map<String, dynamic>>{};
    for (final row in workerDates) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) datesById[id] = Map<String, dynamic>.from(row);
    }
    for (final row in partnerDates) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) datesById[id] = Map<String, dynamic>.from(row);
    }

    return rows.map<Map<String, dynamic>>((row) {
      final value = Map<String, dynamic>.from(row as Map);
      final id = value['id']?.toString() ?? '';
      final dates = datesById[id] ?? const <String, dynamic>{};
      final personnel =
          personnelByWorker[id] ?? const <String, dynamic>{};
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
        'createdAt': dates['created_at'] ?? '',
        'updatedAt': dates['updated_at'] ?? '',
        'bloodType': personnel['blood_type'] ?? '',
        'address': personnel['address'] ?? '',
        'emergencyName': personnel['emergency_name'] ?? '',
        'emergencyRelation': personnel['emergency_relation'] ?? '',
        'emergencyPhone': personnel['emergency_phone'] ?? '',
        'emergencyAddress': personnel['emergency_address'] ?? '',
        'familyComposition': personnel['family_composition'] ?? '',
        'familyMembers': personnel['family_members'] is List
            ? personnel['family_members']
            : const <dynamic>[],
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

    final workerId = inserted['id']?.toString() ?? '';
    if (workerId.isNotEmpty) {
      await _client.rpc(
        'save_worker_personnel_profile',
        params: {
          'p_worker_id': workerId,
          'p_payload': {
            'name': record['name']?.toString() ?? '',
            'kind': kind,
            'blood_type': record['bloodType']?.toString() ?? '',
            'role': record['role']?.toString() ?? '',
            'phone': record['phone']?.toString() ?? '',
            'address': record['address']?.toString() ?? '',
            'emergency_name': record['emergencyName']?.toString() ?? '',
            'emergency_relation':
                record['emergencyRelation']?.toString() ?? '',
            'emergency_phone':
                record['emergencyPhone']?.toString() ?? '',
            'emergency_address':
                record['emergencyAddress']?.toString() ?? '',
            'family_composition':
                record['familyComposition']?.toString() ?? '',
            'family_members': record['familyMembers'] is List
                ? record['familyMembers']
                : const <dynamic>[],
          },
        },
      );
    }

    return {...record, 'id': inserted['id']};
  }

  Future<Map<String, dynamic>> savePersonnelProfile(
    Map<String, dynamic> record,
  ) async {
    final id = record['id']?.toString() ?? '';
    if (id.isEmpty) throw StateError('社員情報を確認できません。');
    final raw = await _client.rpc(
      'save_worker_personnel_profile',
      params: {
        'p_worker_id': id,
        'p_payload': {
          'name': record['name']?.toString() ?? '',
          'kind': record['kind']?.toString() ?? 'employee',
          'blood_type': record['bloodType']?.toString() ?? '',
          'role': record['role']?.toString() ?? '',
          'phone': record['phone']?.toString() ?? '',
          'address': record['address']?.toString() ?? '',
          'emergency_name': record['emergencyName']?.toString() ?? '',
          'emergency_relation':
              record['emergencyRelation']?.toString() ?? '',
          'emergency_phone': record['emergencyPhone']?.toString() ?? '',
          'emergency_address':
              record['emergencyAddress']?.toString() ?? '',
          'family_composition':
              record['familyComposition']?.toString() ?? '',
          'family_members': record['familyMembers'] is List
              ? record['familyMembers']
              : const <dynamic>[],
        },
      },
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> loadPendingPersonnelChanges() async {
    final raw = await _client.rpc('pending_worker_personnel_changes');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> decidePersonnelChange({
    required String requestId,
    required bool approve,
  }) async {
    final raw = await _client.rpc(
      'decide_worker_personnel_change',
      params: {
        'p_request_id': requestId,
        'p_approve': approve,
      },
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
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
