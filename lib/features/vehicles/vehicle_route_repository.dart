import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class VehicleRouteRepository {
  VehicleRouteRepository._(this._client);

  final SupabaseClient _client;

  static VehicleRouteRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return VehicleRouteRepository._(client);
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
    return rows.first['company_id'].toString();
  }

  Future<({bool vehicles, bool routes})> managementPermissions() async {
    final value = await _client.rpc('current_feature_permissions');
    final row = value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
    return (
      vehicles: row['can_manage_vehicles'] == true,
      routes: row['can_manage_routes'] == true,
    );
  }

  Future<List<Map<String, dynamic>>> loadVehicles() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('vehicles')
        .select()
        .eq('company_id', companyId)
        .order('is_active', ascending: false)
        .order('display_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadRoutes() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('route_assignments')
        .select(
          'id, company_id, service_date, route_name, vehicle_id, site_id, driver_user_id, notes, is_active, vehicles(display_name), sites(name)',
        )
        .eq('company_id', companyId)
        .order('service_date', ascending: false)
        .order('route_name');

    final profiles = await _client.rpc('company_member_profiles') as List<dynamic>;
    final names = <String, String>{
      for (final raw in profiles)
        if ((raw as Map)['user_id'] != null)
          raw['user_id'].toString(): raw['display_name']?.toString() ?? 'メンバー',
    };

    return [
      for (final raw in rows)
        {
          ...Map<String, dynamic>.from(raw),
          'driver_name': names[raw['driver_user_id']?.toString()] ?? '',
        },
    ];
  }

  Future<List<Map<String, dynamic>>> loadSites() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('sites')
        .select('id, name, status')
        .eq('company_id', companyId)
        .neq('status', 'completed')
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadDrivers() async {
    final rows = await _client.rpc('company_member_profiles') as List<dynamic>;
    return [
      for (final raw in rows)
        {
          'id': (raw as Map)['user_id']?.toString() ?? '',
          'name': raw['display_name']?.toString() ?? 'メンバー',
        },
    ].where((row) => row['id']!.isNotEmpty).toList(growable: false);
  }

  Future<void> saveVehicle({
    String? id,
    required String displayName,
    String? registrationNumber,
    String? vehicleType,
    int? capacity,
    String? notes,
    bool isActive = true,
  }) async {
    final companyId = await _companyId();
    final userId = _client.auth.currentUser!.id;
    final payload = {
      'company_id': companyId,
      'display_name': displayName.trim(),
      'registration_number': _nullable(registrationNumber),
      'vehicle_type': _nullable(vehicleType),
      'capacity': capacity,
      'notes': _nullable(notes),
      'is_active': isActive,
      'updated_by': userId,
    };
    if (id == null) {
      await _client.from('vehicles').insert({...payload, 'created_by': userId});
    } else {
      await _client.from('vehicles').update(payload).eq('id', id);
    }
  }

  Future<void> setVehicleActive(String id, bool active) async {
    await _client.from('vehicles').update({
      'is_active': active,
      'updated_by': _client.auth.currentUser!.id,
    }).eq('id', id);
  }

  Future<void> saveRoute({
    String? id,
    required DateTime serviceDate,
    required String routeName,
    String? vehicleId,
    String? siteId,
    String? driverUserId,
    String? notes,
    bool isActive = true,
  }) async {
    final companyId = await _companyId();
    final userId = _client.auth.currentUser!.id;
    final payload = {
      'company_id': companyId,
      'service_date': _date(serviceDate),
      'route_name': routeName.trim(),
      'vehicle_id': _nullable(vehicleId),
      'site_id': _nullable(siteId),
      'driver_user_id': _nullable(driverUserId),
      'notes': _nullable(notes),
      'is_active': isActive,
      'updated_by': userId,
    };
    if (id == null) {
      await _client.from('route_assignments').insert({...payload, 'created_by': userId});
    } else {
      await _client.from('route_assignments').update(payload).eq('id', id);
    }
  }

  Future<void> setRouteActive(String id, bool active) async {
    await _client.from('route_assignments').update({
      'is_active': active,
      'updated_by': _client.auth.currentUser!.id,
    }).eq('id', id);
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
