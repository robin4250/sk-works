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

  Future<Map<String, dynamic>> permissions() async {
    final value = await _client.rpc('current_feature_permissions');
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Future<List<Map<String, dynamic>>> vehicles() async {
    final rows = await _client
        .from('vehicles')
        .select('id,display_name,registration_number,vehicle_type,capacity,notes,is_active')
        .order('is_active', ascending: false)
        .order('display_name');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> routes() async {
    final rows = await _client
        .from('route_assignments')
        .select('id,service_date,route_name,vehicle_id,site_id,driver_user_id,notes,is_active')
        .order('service_date', ascending: false)
        .order('route_name');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> sites() async {
    final rows = await _client
        .from('sites')
        .select('id,name,status')
        .neq('status', 'completed')
        .order('name');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> drivers() async {
    final rows = await _client
        .from('workers')
        .select('user_id,name,status')
        .eq('status', 'active')
        .not('user_id', 'is', null)
        .order('name');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<void> saveVehicle({
    String? id,
    required String name,
    String? registrationNumber,
    String? vehicleType,
    int? capacity,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    final membership = await _membership();
    final data = <String, dynamic>{
      'company_id': membership,
      'display_name': name.trim(),
      'registration_number': _nullable(registrationNumber),
      'vehicle_type': _nullable(vehicleType),
      'capacity': capacity,
      'notes': _nullable(notes),
      'updated_by': user.id,
    };
    if (id == null) {
      data['created_by'] = user.id;
      await _client.from('vehicles').insert(data);
    } else {
      await _client.from('vehicles').update(data).eq('id', id);
    }
  }

  Future<void> setVehicleActive(String id, bool active) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    await _client.from('vehicles').update({
      'is_active': active,
      'updated_by': user.id,
    }).eq('id', id);
  }

  Future<void> saveRoute({
    String? id,
    required DateTime serviceDate,
    required String name,
    String? vehicleId,
    String? siteId,
    String? driverUserId,
    String? notes,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    final membership = await _membership();
    final data = <String, dynamic>{
      'company_id': membership,
      'service_date': serviceDate.toIso8601String().substring(0, 10),
      'route_name': name.trim(),
      'vehicle_id': _nullable(vehicleId),
      'site_id': _nullable(siteId),
      'driver_user_id': _nullable(driverUserId),
      'notes': _nullable(notes),
      'updated_by': user.id,
    };
    if (id == null) {
      data['created_by'] = user.id;
      await _client.from('route_assignments').insert(data);
    } else {
      await _client.from('route_assignments').update(data).eq('id', id);
    }
  }

  Future<void> setRouteActive(String id, bool active) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    await _client.from('route_assignments').update({
      'is_active': active,
      'updated_by': user.id,
    }).eq('id', id);
  }

  Future<String> _membership() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    final rows = await _client
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) throw StateError('会社情報が見つかりません。');
    return rows.first['company_id'].toString();
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
