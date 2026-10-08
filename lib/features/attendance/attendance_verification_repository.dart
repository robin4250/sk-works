// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'gps_photo_capture_result.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'attendance_shift_context.dart';
import 'attendance_work_date.dart';

enum HomeAttendancePhase {
  notStarted,
  working,
  finished,
}

class HomeAttendanceStatus {
  const HomeAttendanceStatus({
    this.verificationMode = 'none',
    this.siteName,
    this.clockIn,
    this.clockOut,
    this.selectedVehicleId,
    this.selectedVehicleName,
    this.selectedRouteId,
    this.selectedRouteName,
    this.gpsWeekdays = const [],
    this.gpsTime,
    this.phase = HomeAttendancePhase.notStarted,
    this.openShifts = const [],
  });

  final String verificationMode;
  final String? siteName;
  final DateTime? clockIn;
  final DateTime? clockOut;
  final String? selectedVehicleId;
  final String? selectedVehicleName;
  final String? selectedRouteId;
  final String? selectedRouteName;
  final List<int> gpsWeekdays;
  final String? gpsTime;
  final HomeAttendancePhase phase;
  final List<AttendanceShiftContext> openShifts;

  String get verificationModeLabel => switch (verificationMode) {
        'none' => '未選択',
        'location' || 'gps_auto' => 'GPS自動出勤',
        'location_photo' => '位置情報＋写真',
        'photo' => '写真',
        _ => '手動',
      };

  String get phaseLabel => switch (phase) {
        HomeAttendancePhase.working => '出勤中',
        HomeAttendancePhase.finished => '本日は退勤済',
        HomeAttendancePhase.notStarted => '未出勤',
      };
}

class AttendanceVerificationRepository {
  AttendanceVerificationRepository._(this._client);

  final SupabaseClient _client;
  static const _bucket = 'attendance-evidence';

  static AttendanceVerificationRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return AttendanceVerificationRepository._(client);
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

  Future<bool> canManageAttendance() async {
    final value = await _client.rpc('current_feature_permissions');
    if (value is! Map) return false;
    final permissions = Map<String, dynamic>.from(value);
    return permissions['can_manage_attendance'] == true;
  }

  Future<Map<String, dynamic>> loadAttendanceSelectionWorkspace() async {
    final raw = await _client.rpc('my_attendance_selection_workspace');
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Future<void> saveAttendanceSelection({
    required String mode,
    String? siteId,
    List<int>? weekdays,
    String? localTime,
  }) async {
    final workerValue = await _client.rpc('ensure_current_user_worker');
    final workerId = workerValue?.toString() ?? '';
    if (workerId.isEmpty) throw StateError('社員情報を確認できません。');

    final companyId = await _companyId();
    final workDate = DateTime.now().year.toString().padLeft(4, '0') +
        '-' +
        DateTime.now().month.toString().padLeft(2, '0') +
        '-' +
        DateTime.now().day.toString().padLeft(2, '0');

    if (siteId != null && siteId.trim().isNotEmpty) {
      await _client
          .from('work_attendance_selections')
          .update({
            'route_assignment_id': null,
            'updated_by': _client.auth.currentUser?.id,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('company_id', companyId)
          .eq('worker_id', workerId)
          .eq('work_date', workDate);

      await _client.rpc(
        'save_my_attendance_selection',
        params: {
          'p_mode': mode,
          'p_site_id': siteId,
          'p_weekdays': weekdays,
          'p_local_time': localTime,
          'p_timezone': 'Asia/Tokyo',
        },
      );

      await _client
          .from('work_vehicle_route_selections')
          .update({
            'route_assignment_id': null,
            'updated_by': _client.auth.currentUser?.id,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('company_id', companyId)
          .eq('worker_id', workerId)
          .eq('work_date', workDate);
      return;
    }

    final routeRow = await _client
        .from('work_vehicle_route_selections')
        .select('route_assignment_id')
        .eq('company_id', companyId)
        .eq('worker_id', workerId)
        .eq('work_date', workDate)
        .maybeSingle();
    final routeId = routeRow?['route_assignment_id']?.toString();

    if (routeId != null && routeId.isNotEmpty) {
      await _client.rpc(
        'save_my_route_attendance_selection',
        params: {
          'p_mode': mode,
          'p_route_assignment_id': routeId,
          'p_weekdays': weekdays,
          'p_local_time': localTime,
          'p_timezone': 'Asia/Tokyo',
        },
      );
      return;
    }

    if (mode == 'gps_auto') {
      throw StateError('GPS自動出勤は現場またはルートの選択が必要です。');
    }

    await _client.from('work_attendance_selections').upsert(
      {
        'company_id': companyId,
        'worker_id': workerId,
        'work_date': workDate,
        'verification_mode': mode,
        'site_id': null,
        'route_assignment_id': null,
        'updated_by': _client.auth.currentUser?.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'company_id,worker_id,work_date',
    );
  }

  Future<Map<String, dynamic>> attemptGpsAutoAttendance({
    required double latitude,
    required double longitude,
    required double accuracyM,
  }) async {
    final raw = await _client.rpc(
      'attempt_gps_auto_attendance',
      params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_accuracy_m': accuracyM,
      },
    );
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final companyId = await _companyId();
    final row = await _client
        .from('attendance_verification_settings')
        .select('company_id, mode, proximity_radius_m')
        .eq('company_id', companyId)
        .maybeSingle();
    if (row == null) {
      return {
        'company_id': companyId,
        'mode': 'manual',
        'proximity_radius_m': 300,
      };
    }
    return Map<String, dynamic>.from(row);
  }

  Future<HomeAttendanceStatus> loadHomeAttendanceStatus() async {
    final workspace = await loadAttendanceSelectionWorkspace();
    final dailySelection = workspace['selection'] is Map
        ? Map<String, dynamic>.from(workspace['selection'] as Map)
        : const <String, dynamic>{};
    final gpsSchedule = workspace['gps_schedule'] is Map
        ? Map<String, dynamic>.from(workspace['gps_schedule'] as Map)
        : const <String, dynamic>{};

    final workerValue = await _client.rpc('ensure_current_user_worker');
    final workerId = workerValue?.toString();
    if (workerId == null || workerId.isEmpty) {
      const fallbackMode = 'none';
      return HomeAttendanceStatus(verificationMode: fallbackMode);
    }

    final now = DateTime.now();
    final scheduleWeekdays = gpsSchedule['weekdays'] is List
        ? (gpsSchedule['weekdays'] as List)
            .map((value) => (value as num).toInt())
            .toList(growable: false)
        : const <int>[];
    final scheduledToday =
        gpsSchedule['enabled'] == true && scheduleWeekdays.contains(now.weekday);
    final configuredMode = dailySelection['mode']?.toString() ??
        (scheduledToday ? 'gps_auto' : 'none');
    final workDate =
        now.year.toString().padLeft(4, '0') +
        '-' +
        now.month.toString().padLeft(2, '0') +
        '-' +
        now.day.toString().padLeft(2, '0');
    Map<String, dynamic>? selection;
    try {
      final row = await _client
          .from('work_vehicle_route_selections')
          .select(
            'vehicle_id,route_assignment_id,'
            'vehicles(display_name),route_assignments(route_name)',
          )
          .eq('worker_id', workerId)
          .eq('work_date', workDate)
          .maybeSingle();
      if (row != null) selection = Map<String, dynamic>.from(row);
    } catch (_) {
      selection = null;
    }
    final selectedVehicle = selection?['vehicles'];
    final selectedRoute = selection?['route_assignments'];

    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final rows = await _client
        .from('attendance_verifications')
        .select('id, worker_id, event_type, verification_mode, confirmed_at, work_date, source_clock_in_id, site_id, route_assignment_id, vehicle_id, sites(name), route_assignments(route_name), vehicles(display_name), daily_reports(report_date)')
        .eq('worker_id', workerId)
        .gte('confirmed_at', DateTime(now.year, now.month, now.day - 1).toUtc().toIso8601String())
        .lt('confirmed_at', end.toUtc().toIso8601String())
        .order('confirmed_at');

    final openShifts = openAttendanceShifts(
      List<Map<String, dynamic>>.from(rows), workerId: workerId, now: now,
    );
    final activeShift = openShifts.length == 1 ? openShifts.single : null;
    DateTime? clockIn = activeShift?.clockIn;
    DateTime? clockOut;
    String? siteName = openShifts.length > 1 ? null : activeShift == null ? dailySelection['site_name']?.toString() : (activeShift.siteName ?? activeShift.routeName);
    if (openShifts.isEmpty && (siteName ?? '').isEmpty && scheduledToday) {
      siteName = gpsSchedule['site_name']?.toString();
    }
    String? latestEventType;

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final confirmed =
          DateTime.tryParse(row['confirmed_at']?.toString() ?? '')?.toLocal();
      final eventType = row['event_type']?.toString();
      if (confirmed == null || attendanceEventWorkDate(confirmed, row['daily_reports'], workDate: row['work_date']) != start) continue;
      final site = row['sites'];

      if (openShifts.isEmpty && (siteName ?? '').isEmpty &&
          site is Map &&
          (site['name']?.toString().trim().isNotEmpty ?? false)) {
        siteName = site['name'].toString();
      }
      if (openShifts.isEmpty) {
        if (eventType == 'clock_in') {
          clockIn ??= confirmed;
        } else if (eventType == 'clock_out') {
          clockOut = confirmed;
        }
      }
      if (eventType == 'clock_in' || eventType == 'clock_out') {
        latestEventType = eventType;
      }
    }

    final phase = openShifts.isNotEmpty ? HomeAttendancePhase.working : switch (latestEventType) {
      'clock_in' => HomeAttendancePhase.working,
      'clock_out' => HomeAttendancePhase.finished,
      _ => HomeAttendancePhase.notStarted,
    };

    return HomeAttendanceStatus(
      verificationMode: configuredMode,
      siteName: siteName,
      clockIn: clockIn,
      clockOut: clockOut,
      selectedVehicleId: selection?['vehicle_id']?.toString(),
      selectedVehicleName:
          selectedVehicle is Map ? selectedVehicle['display_name']?.toString() : null,
      selectedRouteId: selection?['route_assignment_id']?.toString(),
      selectedRouteName:
          selectedRoute is Map ? selectedRoute['route_name']?.toString() : null,
      gpsWeekdays: scheduleWeekdays,
      gpsTime: gpsSchedule['local_time']?.toString(),
      phase: phase,
      openShifts: openShifts,
    );
  }

  Future<void> saveSettings({
    required String mode,
    required int proximityRadiusM,
  }) async {
    if (!await canManageAttendance()) {
      throw StateError('出勤確認方法を変更する権限がありません。');
    }
    final companyId = await _companyId();
    await _client.from('attendance_verification_settings').upsert({
      'company_id': companyId,
      'mode': mode,
      'proximity_radius_m': proximityRadiusM,
      'updated_by': _client.auth.currentUser?.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadWorkers() async {
    final companyId = await _companyId();
    final workerId = await _client.rpc('ensure_current_user_worker');
    final id = workerId?.toString();
    if (id == null || id.isEmpty) return const [];

    final rows = await _client
        .from('workers')
        .select('id, name')
        .eq('company_id', companyId)
        .eq('id', id)
        .limit(1);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> loadSites() async {
    final companyId = await _companyId();
    final rows = await _client
        .from('sites')
        .select('id, name, address, latitude, longitude, status')
        .eq('company_id', companyId)
        .order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> updateSiteLocation({
    required String siteId,
    required double latitude,
    required double longitude,
  }) async {
    if (!await canManageAttendance()) {
      throw StateError('現場の基準位置を変更する権限がありません。');
    }

    await _client.rpc(
      'update_site_attendance_location',
      params: {
        'p_site_id': siteId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );
  }

  Future<List<Map<String, dynamic>>> loadRecent({int limit = 20}) async {
    final companyId = await _companyId();
    final rows = await _client
        .from('attendance_verifications')
        .select(
          'id, event_type, verification_mode, confirmed_at, '
          'proximity_status, distance_to_site_m, workers(name), '
          'sites(name), route_assignments(route_name)',
        )
        .eq('company_id', companyId)
        .order('confirmed_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> captureCompanyId() => _companyId();

  Future<bool> captureEnabled() async {
    final companyId = await _companyId();
    try {
      final value = await _client.rpc('get_attendance_capture_capability',
        params: {'p_company_id': companyId});
      return value is Map && value['version'] == 1 &&
        value['company_id'] == companyId && value['capture_enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> uploadCapturedPhoto(CapturedPhoto photo, CaptureShiftContext context,
      String workerId) async {
    if (context.companyId != await _companyId()) {
      throw StateError('撮影中に会社が変更されました');
    }
    final path = '${context.companyId}/attendance/${context.siteId ?? context.routeId ?? 'route'}/$workerId/${DateTime.now().microsecondsSinceEpoch}.jpg';
    await _client.storage.from(_bucket).uploadBinary(path, photo.bytes,
      fileOptions: const FileOptions(upsert: false));
    return path;
  }

  Future<Map<String, dynamic>> createVerification({
    required String workerId,
    String? siteId,
    required String eventType,
    required String verificationMode,
    double? latitude,
    double? longitude,
    double? accuracyM,
    double? distanceToSiteM,
    required String proximityStatus,
    Uint8List? photoBytes,
    String? photoFilename,
    String? note,
    AttendanceShiftContext? shift,
    GpsPhotoCaptureResult? capture,
  }) async {
    final companyId = await _companyId();
    if (shift != null && (eventType != 'clock_out' || shift.workerId != workerId || shift.siteId != siteId)) {
      throw StateError('退勤対象の勤務を確認してください');
    }

    Map<String, dynamic>? selection;
    try {
      final row = await _client
          .from('work_vehicle_route_selections')
          .select('vehicle_id,route_assignment_id')
          .eq('company_id', companyId)
          .eq('worker_id', workerId)
          .eq(
            'work_date',
            DateTime.now().year.toString().padLeft(4, '0') +
                '-' +
                DateTime.now().month.toString().padLeft(2, '0') +
                '-' +
                DateTime.now().day.toString().padLeft(2, '0'),
          )
          .maybeSingle();
      if (row != null) selection = Map<String, dynamic>.from(row);
    } catch (_) {
      selection = null;
    }

    if (shift != null) {
      selection = {'vehicle_id': shift.vehicleId, 'route_assignment_id': shift.routeId};
    }
    final routeId = selection?['route_assignment_id']?.toString();
    if ((siteId == null || siteId.trim().isEmpty) &&
        (routeId == null || routeId.trim().isEmpty)) {
      throw StateError('現場またはルートを選択してください。');
    }

    if (capture != null && (verificationMode != 'location_photo' ||
        capture.context.companyId != companyId ||
        capture.context.sourceClockInId != shift?.id ||
        capture.context.siteId != siteId ||
        capture.context.routeId != routeId ||
        capture.context.vehicleId != selection?['vehicle_id']?.toString() ||
        !await captureEnabled())) {
      throw StateError('撮影対象の勤務を再確認してください');
    }
    String? storagePath = capture?.storagePath;

    if (capture == null && photoBytes != null) {
      final extension = _extensionOf(photoFilename ?? 'attendance.jpg');
      final objectName =
          '${DateTime.now().microsecondsSinceEpoch}$extension';
      storagePath =
          '$companyId/attendance/${siteId ?? routeId ?? 'route'}/$workerId/$objectName';
      await _client.storage.from(_bucket).uploadBinary(
            storagePath,
            photoBytes,
            fileOptions: const FileOptions(upsert: false),
          );
    }

    try {
      final row = await _client
          .from('attendance_verifications')
          .insert({
            'company_id': companyId,
            'worker_id': workerId,
            'site_id': _nullable(siteId),
            'event_type': eventType,
            if (shift != null) 'source_clock_in_id': shift.id,
            'verification_mode': verificationMode,
            'latitude': latitude,
            'longitude': longitude,
            'accuracy_m': accuracyM,
            'distance_to_site_m': distanceToSiteM,
            'proximity_status': proximityStatus,
            'photo_storage_path': storagePath,
            if (capture != null) ...capture.insertMetadata,
            'note': _nullable(note),
            'vehicle_id': selection?['vehicle_id'],
            'route_assignment_id': selection?['route_assignment_id'],
            'created_by': _client.auth.currentUser?.id,
          })
          .select('id, confirmed_at, work_date, source_clock_in_id')
          .single();
      return Map<String, dynamic>.from(row);
    } catch (_) {
      if (capture == null && storagePath != null) {
        try {
          await _client.storage.from(_bucket).remove([storagePath]);
        } catch (_) {
          // Preserve the original persistence failure.
        }
      }
      rethrow;
    }
  }

  String _extensionOf(String filename) {
    final lastDot = filename.lastIndexOf('.');
    if (lastDot < 0 || lastDot == filename.length - 1) return '.jpg';
    final ext = filename.substring(lastDot).toLowerCase();
    if (ext.length > 8) return '.jpg';
    final cleaned = ext.replaceAll(RegExp(r'[^a-z0-9.]'), '');
    return cleaned.isEmpty ? '.jpg' : cleaned;
  }

  Object? _nullable(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
