// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

class VehicleRouteRepository {
  VehicleRouteRepository._(this._client);

  final SupabaseClient _client;
  static const _documentBucket = 'vehicle-documents';

  static VehicleRouteRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return VehicleRouteRepository._(client);
  }

  Future<Map<String, dynamic>> permissions() async {
    final user = _client.auth.currentUser;
    if (user == null) return const {};
    final rows = await _client
        .from('company_members')
        .select('role')
        .eq('user_id', user.id)
        .limit(1);
    final role = rows.isEmpty ? '' : rows.first['role']?.toString() ?? '';
    final canManage = role == 'owner' || role == 'admin' || role == 'manager';
    return {
      'can_manage_vehicles': canManage,
      'can_manage_routes': canManage,
    };
  }

  Future<List<Map<String, dynamic>>> vehicles({bool activeOnly = false}) async {
    var query = _client.from('vehicles').select(
      'id,display_name,registration_number,odometer_km,storage_address,'
      'registration_document_path,compulsory_insurance_path,'
      'voluntary_insurance_path,notes,is_active,created_at,updated_at',
    );
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query
        .order('is_active', ascending: false)
        .order('display_name');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<List<Map<String, dynamic>>> routes({bool activeOnly = false}) async {
    var query = _client.from('route_assignments').select(
      'id,route_name,notes,is_active,created_at,updated_at,'
      'route_stops(id,stop_order,site_id,address,source_kind,source_id,source_label,latitude,longitude,sites(name,address,latitude,longitude))',
    );
    if (activeOnly) query = query.eq('is_active', true);
    final rows = await query
        .order('is_active', ascending: false)
        .order('route_name');
    return [
      for (final raw in rows)
        {
          ...Map<String, dynamic>.from(raw),
          'route_stops': _sortedStops(raw['route_stops']),
        },
    ];
  }

  Future<List<Map<String, dynamic>>> sites() async {
    final rows = await _client
        .from('sites')
        .select('id,name,address,latitude,longitude,status')
        .neq('status', 'completed')
        .order('name');
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      routeCompanyDirectories() async {
    final raw = await _client.rpc('site_map_workspace');
    final value = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};

    List<Map<String, dynamic>> rows(String key) {
      final source = value[key];
      if (source is! List) return const [];
      return source
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

    return {
      'customers': rows('customers'),
      'partners': rows('partners'),
    };
  }

  Future<String> saveVehicle({
    String? id,
    required String name,
    required String registrationNumber,
    required double odometerKm,
    required String storageAddress,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    final companyId = await _membership();
    final data = <String, dynamic>{
      'company_id': companyId,
      'display_name': name.trim(),
      'registration_number': _nullable(registrationNumber),
      'odometer_km': odometerKm,
      'storage_address': _nullable(storageAddress),
      'updated_by': user.id,
    };

    if (id == null) {
      data['created_by'] = user.id;
      final row = await _client
          .from('vehicles')
          .insert(data)
          .select('id')
          .single();
      return row['id'].toString();
    }

    await _client.from('vehicles').update(data).eq('id', id);
    return id;
  }

  Future<void> uploadVehicleDocument({
    required String vehicleId,
    required String kind,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final column = switch (kind) {
      'registration' => 'registration_document_path',
      'compulsory' => 'compulsory_insurance_path',
      'voluntary' => 'voluntary_insurance_path',
      _ => throw ArgumentError.value(kind, 'kind', 'unknown vehicle document'),
    };

    final companyId = await _membership();
    final rows = await _client
        .from('vehicles')
        .select('id,' + column)
        .eq('id', vehicleId)
        .eq('company_id', companyId)
        .limit(1);
    if (rows.isEmpty) throw StateError('車両が見つかりません。');

    final oldPath = rows.first[column]?.toString();
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = companyId +
        '/' +
        vehicleId +
        '/' +
        kind +
        '/' +
        DateTime.now().microsecondsSinceEpoch.toString() +
        '_' +
        safe;

    await _client.storage.from(_documentBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );

    try {
      await _client.from('vehicles').update({
        column: path,
        'updated_by': _client.auth.currentUser?.id,
      }).eq('id', vehicleId);
      if (oldPath != null && oldPath.isNotEmpty && oldPath != path) {
        await _client.storage.from(_documentBucket).remove([oldPath]);
      }
    } catch (_) {
      await _client.storage.from(_documentBucket).remove([path]);
      rethrow;
    }
  }

  Future<List<String>> notifyMissingVehicleDocuments(
    String vehicleId,
  ) async {
    final value = await _client.rpc(
      'notify_missing_vehicle_documents',
      params: {'p_vehicle_id': vehicleId},
    );
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList(growable: false);
  }

  Future<void> setVehicleActive(String id, bool active) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    await _client.from('vehicles').update({
      'is_active': active,
      'updated_by': user.id,
    }).eq('id', id);
  }

  Future<String> saveRoute({
    String? id,
    required String name,
    required String notes,
    required List<Map<String, Object?>> stops,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    final companyId = await _membership();
    final data = <String, dynamic>{
      'company_id': companyId,
      'route_name': name.trim(),
      'service_date': null,
      'vehicle_id': null,
      'site_id': null,
      'driver_user_id': null,
      'notes': _nullable(notes),
      'updated_by': user.id,
    };

    String routeId;
    if (id == null) {
      data['created_by'] = user.id;
      final row = await _client
          .from('route_assignments')
          .insert(data)
          .select('id')
          .single();
      routeId = row['id'].toString();
    } else {
      await _client.from('route_assignments').update(data).eq('id', id);
      routeId = id;
      await _client.from('route_stops').delete().eq('route_assignment_id', id);
    }

    if (stops.isNotEmpty) {
      await _client.from('route_stops').insert([
        for (var i = 0; i < stops.length; i++)
          {
            'company_id': companyId,
            'route_assignment_id': routeId,
            'stop_order': i,
            'site_id': _nullable(stops[i]['site_id']),
            'address': _nullable(stops[i]['address']),
            'source_kind': _nullable(stops[i]['source_kind']),
            'source_id': _nullable(stops[i]['source_id']),
            'source_label': _nullable(stops[i]['source_label']),
            'latitude': stops[i]['latitude'],
            'longitude': stops[i]['longitude'],
            'created_by': user.id,
            'updated_by': user.id,
          },
      ]);
    }
    return routeId;
  }

  Future<void> setRouteActive(String id, bool active) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('ログインが必要です。');
    await _client.from('route_assignments').update({
      'is_active': active,
      'updated_by': user.id,
    }).eq('id', id);
  }

  Future<Map<String, dynamic>> loadTodaySelection() async {
    final companyId = await _membership();
    final workerValue = await _client.rpc('ensure_current_user_worker');
    final workerId = workerValue?.toString() ?? '';
    if (workerId.isEmpty) return const {};

    final row = await _client
        .from('work_vehicle_route_selections')
        .select(
          'vehicle_id,route_assignment_id,updated_at,'
          'vehicles(display_name,registration_number,odometer_km),'
          'route_assignments(route_name)',
        )
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('work_date', _date(DateTime.now()))
        .maybeSingle();
    return row == null ? const {} : Map<String, dynamic>.from(row);
  }

  Future<void> saveTodaySelection({
    String? vehicleId,
    String? routeId,
  }) async {
    final companyId = await _membership();
    final workerValue = await _client.rpc('ensure_current_user_worker');
    final workerId = workerValue?.toString() ?? '';
    if (workerId.isEmpty) throw StateError('社員情報を確認できません。');

    await _client.from('work_vehicle_route_selections').upsert(
      {
        'company_id': companyId,
        'worker_id': workerId,
        'work_date': _date(DateTime.now()),
        'vehicle_id': _nullable(vehicleId),
        'route_assignment_id': _nullable(routeId),
        'updated_by': _client.auth.currentUser?.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'company_id,worker_id,work_date',
    );
  }

  Future<void> updateOdometer({
    required String vehicleId,
    required double odometerKm,
  }) async {
    final companyId = await _membership();
    final rows = await _client
        .from('vehicles')
        .select('odometer_km')
        .eq('id', vehicleId)
        .eq('company_id', companyId)
        .limit(1);
    if (rows.isEmpty) throw StateError('車両が見つかりません。');

    final current = (rows.first['odometer_km'] as num?)?.toDouble() ?? 0;
    if (odometerKm < current) {
      throw StateError('現在の走行距離より小さい数値は登録できません。');
    }

    await _client.from('vehicles').update({
      'odometer_km': odometerKm,
      'updated_by': _client.auth.currentUser?.id,
    }).eq('id', vehicleId);
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

  List<Map<String, dynamic>> _sortedStops(Object? value) {
    if (value is! List) return const [];
    final rows = value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    rows.sort(
      (a, b) => ((a['stop_order'] as num?)?.toInt() ?? 0)
          .compareTo((b['stop_order'] as num?)?.toInt() ?? 0),
    );
    return rows;
  }

  String _date(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return year + '-' + month + '-' + day;
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
