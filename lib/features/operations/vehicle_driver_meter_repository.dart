import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'vehicle_driver_meter_input.dart';

abstract interface class VehicleDriverMeterSource {
  Future<Map<String, dynamic>?> claim(String sourceClockInId);
  Future<bool> isDriver(String companyId, String workerId);
  Future<bool> isEnabled(String companyId);
  Future<Map<String, dynamic>?> event(String sourceClockInId);
  Future<Map<String, dynamic>> record(Map<String, Object?> parameters);
}

class VehicleDriverMeterContext {
  const VehicleDriverMeterContext({
    required this.sourceClockInId,
    required this.companyId,
    required this.workerId,
    required this.workDate,
    required this.previousKm,
    required this.checkedOut,
    this.siteId,
    this.routeId,
    this.vehicleLabel,
    this.event,
  });
  final String sourceClockInId;
  final String companyId;
  final String workerId;
  final String workDate;
  final double? previousKm;
  final bool checkedOut;
  final String? siteId;
  final String? routeId;
  final String? vehicleLabel;
  final Map<String, dynamic>? event;
  bool get canRecord => checkedOut && previousKm != null && event == null;
}

class VehicleDriverMeterRepository {
  VehicleDriverMeterRepository(this._source);
  final VehicleDriverMeterSource _source;
  final Map<String, String> _operationIds = {};

  static VehicleDriverMeterRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized || SupabaseBackend.client.auth.currentUser == null) {
      return null;
    }
    return VehicleDriverMeterRepository(_SupabaseVehicleDriverMeterSource(SupabaseBackend.client));
  }

  /// Missing capability/schema is unavailable, never implicitly enabled.
  Future<VehicleDriverMeterContext?> load(String sourceClockInId) async {
    if (sourceClockInId.isEmpty) {
      return null;
    }
    final claim = await _source.claim(sourceClockInId);
    if (claim == null || claim['source_clock_in_id'] != sourceClockInId) {
      return null;
    }
    final company = claim['company_id']?.toString() ?? '';
    final worker = claim['driver_worker_id']?.toString() ?? '';
    final workDate = claim['work_date']?.toString() ?? '';
    if (company.isEmpty || worker.isEmpty || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(workDate)) {
      return null;
    }
    if (!await _source.isDriver(company, worker) || !await _source.isEnabled(company)) {
      return null;
    }
    final event = await _source.event(sourceClockInId);
    if (event != null && (event['source_clock_in_id'] != sourceClockInId ||
        event['company_id'] != company || event['driver_worker_id'] != worker || event['work_date'] != workDate)) {
      throw StateError('Vehicle meter snapshot target mismatch');
    }
    final previous = _number(claim['start_odometer_km']);
    final start = claim['clock_in'];
    final vehicle = claim['vehicle'];
    if (event?['id'] != null) {
      _operationIds[sourceClockInId] = event!['id'].toString();
    }
    return VehicleDriverMeterContext(
      sourceClockInId: sourceClockInId, companyId: company, workerId: worker,
      workDate: workDate, previousKm: previous, checkedOut: claim['ended_at'] != null,
      siteId: start is Map ? start['site_id']?.toString() : null,
      routeId: start is Map ? start['route_assignment_id']?.toString() : null,
      vehicleLabel: vehicle is Map ? [vehicle['display_name'], vehicle['registration_number']]
        .where((value) => value != null && value.toString().isNotEmpty).join(' / ') : null,
      event: event == null ? null : Map.unmodifiable(event),
    );
  }

  Future<Map<String, dynamic>> save(VehicleDriverMeterContext context, VehicleDriverMeterInput input) async {
    bool validNumber(double value) => value.isFinite && value >= 0 && value <= 99999999999.9 &&
        (value * 10).roundToDouble() / 10 == value;
    final previous = context.previousKm;
    if (previous == null || !validNumber(input.currentKm) ||
        (input.manualDistanceKm != null && !validNumber(input.manualDistanceKm!)) ||
        (input.currentKm < previous ? input.manualDistanceKm == null : input.manualDistanceKm != null)) {
      throw StateError('Vehicle meter input requires a valid reading and distance');
    }
    // Recheck driver and capability before RPC; server performs its own checks.
    if (!context.canRecord || !await _source.isDriver(context.companyId, context.workerId) ||
        !await _source.isEnabled(context.companyId)) throw StateError('Vehicle meter is unavailable');
    final id = _operationIds.putIfAbsent(context.sourceClockInId, _newEventId);
    final result = await _source.record({
      'p_source_clock_in_id': context.sourceClockInId, 'p_event_id': id,
      'p_current_km': input.currentKm, 'p_manual_distance_km': input.manualDistanceKm,
    });
    if (result['id'] != id || result['source_clock_in_id'] != context.sourceClockInId ||
        result['company_id'] != context.companyId || result['driver_worker_id'] != context.workerId ||
        result['work_date'] != context.workDate || _number(result['current_km']) != input.currentKm ||
        _number(result['previous_km']) != previous ||
        result['baseline_decreased'] != (input.currentKm < previous) ||
        _number(result['distance_km']) != (input.manualDistanceKm ??
          ((input.currentKm * 10).round() - (previous * 10).round()) / 10)) {
      throw StateError('Vehicle meter save response target mismatch');
    }
    return Map.unmodifiable(result);
  }

  static double? _number(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite && number >= 0 ? number : null;
  }

  static String _newEventId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class _SupabaseVehicleDriverMeterSource implements VehicleDriverMeterSource {
  const _SupabaseVehicleDriverMeterSource(this.client);
  final SupabaseClient client;

  @override
  Future<Map<String, dynamic>?> claim(String id) async => await client
      .from('vehicle_usage_claims')
      .select('source_clock_in_id,company_id,driver_worker_id,work_date,start_odometer_km,ended_at,'
        'clock_in:attendance_verifications!vehicle_usage_claims_source_clock_in_id_fkey(site_id,route_assignment_id),'
        'vehicle:vehicles(display_name,registration_number)')
      .eq('source_clock_in_id', id).maybeSingle();

  @override
  Future<bool> isDriver(String company, String worker) async {
    final user = client.auth.currentUser;
    if (user == null) {
      return false;
    }
    final rows = await client.from('workers').select('id').eq('id', worker)
        .eq('company_id', company).eq('user_id', user.id).eq('status', 'active').limit(1);
    return rows.isNotEmpty;
  }

  @override
  Future<bool> isEnabled(String company) async {
    final value = await client.rpc('get_attendance_rollout_capabilities', params: {'p_company_id': company});
    return vehicleDriverMeterEnabledFor(value, company);
  }

  @override
  Future<Map<String, dynamic>?> event(String id) async => await client
      .from('vehicle_meter_events').select().eq('source_clock_in_id', id).maybeSingle();

  @override
  Future<Map<String, dynamic>> record(Map<String, Object?> parameters) async {
    final result = await client.rpc('record_vehicle_driver_meter', params: parameters);
    if (result is! Map) {
      throw StateError('Vehicle meter save response unavailable');
    }
    return Map<String, dynamic>.from(result);
  }
}

bool vehicleDriverMeterEnabledFor(Object? value, String companyId) =>
    value is Map && value['version'] == 1 && value['company_id'] == companyId &&
    value['vehicle_usage_enabled'] == true && value['vehicle_meter_enabled'] == true;
