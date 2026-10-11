import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'daily_report_shift_context.dart';
import 'daily_report_evidence_address.dart';
import '../attendance/attendance_capture_metadata_service.dart';
import 'daily_report_pdf_evidence.dart';
import '../attendance/group_checkout_repository.dart';
import 'group_daily_report_roster.dart';
import 'vehicle_report_snapshot.dart';
import '../notifications/saved_group_report_publication.dart';
import '../notifications/saved_report_notification_retry_store.dart';

class DailyReportWorkerDraft {
  DailyReportWorkerDraft({
    required this.workerId,
    required this.workerName,
    this.overtimeHours = 0,
    this.earlyHours = 0,
    this.nightHours = 0,
    this.allowanceAmount = 0,
    this.allowanceLabel = '',
    this.vehicleId,
    this.vehicleName,
    this.routeId,
    this.routeName,
    this.odometerKm,
    this.sourceClockInId,
    this.sourceClockOutAt,
    this.meterManaged = false,
    this.meterEventId,
    this.meterSourceClockInId,
    this.previousOdometerKm,
    this.tripDistanceKm,
  });

  final String workerId;
  final String workerName;
  double overtimeHours;
  double earlyHours;
  double nightHours;
  int allowanceAmount;
  String allowanceLabel;
  String? vehicleId;
  String? vehicleName;
  String? routeId;
  String? routeName;
  double? odometerKm;
  final String? sourceClockInId;
  final DateTime? sourceClockOutAt;
  bool meterManaged;
  String? meterEventId;
  String? meterSourceClockInId;
  double? previousOdometerKm;
  double? tripDistanceKm;

  Map<String, Object?> toRpcJson() => {
        'worker_id': workerId,
        'overtime_hours': overtimeHours,
        'early_hours': earlyHours,
        'night_hours': nightHours,
        'allowance_amount': allowanceAmount,
        'allowance_label': allowanceLabel,
      };
}

class DailyReportSiteGroup {
  const DailyReportSiteGroup({
    required this.siteName,
    required this.workers,
    this.siteId,
    this.routeAssignmentId,
  });

  final String? siteId;
  final String? routeAssignmentId;
  final String siteName;
  final List<DailyReportWorkerDraft> workers;

  String get destinationKey => siteId != null
      ? 'site:$siteId'
      : 'route:$routeAssignmentId';
}

class DailyReportRecord {
  const DailyReportRecord({
    required this.id,
    this.siteId,
    this.routeAssignmentId,
    required this.siteName,
    required this.date,
    required this.workDescription,
    required this.status,
    required this.workers,
    this.signerName,
    this.signatureJson,
    this.reporterSignerName,
    this.reporterSignatureJson,
    this.responsibleSignerName,
    this.responsibleSignatureJson,
    this.signedAt,
    this.notificationRetryScope,
  });

  final String id;
  final String? siteId;
  final String? routeAssignmentId;
  final String siteName;
  final DateTime date;
  final String workDescription;
  final String status;
  final List<DailyReportWorkerDraft> workers;
  final String? signerName;
  final Object? signatureJson;
  final String? reporterSignerName;
  final Object? reporterSignatureJson;
  final String? responsibleSignerName;
  final Object? responsibleSignatureJson;
  final DateTime? signedAt;
  final SavedReportNotificationRetry? notificationRetryScope;

  bool get signed => status == 'signed';
}

class DailyReportEvidenceRecord {
  const DailyReportEvidenceRecord({
    required this.id,
    required this.workerName,
    required this.eventType,
    required this.confirmedAt,
    required this.storagePath,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.gpsStatus, this.photoStatus, this.capturedAddress,
    this.photoCapturedAt, this.gpsCapturedAt, this.photoObservedAt,
    this.storageBucket = 'attendance-evidence', this.stopLabel,
    this.sourceClockInId, this.routeStopId, this.originKind,
    this.timeOnly = false,
  });

  DailyReportEvidenceRecord withCapturedAddress(String? address) =>
      DailyReportEvidenceRecord(
        id: id, workerName: workerName, eventType: eventType,
        confirmedAt: confirmedAt, storagePath: storagePath,
        latitude: latitude, longitude: longitude, accuracyM: accuracyM,
        gpsStatus: gpsStatus, photoStatus: photoStatus, capturedAddress: address,
        photoCapturedAt: photoCapturedAt, gpsCapturedAt: gpsCapturedAt,
        photoObservedAt: photoObservedAt, storageBucket: storageBucket,
        stopLabel: stopLabel, sourceClockInId: sourceClockInId,
        routeStopId: routeStopId, originKind: originKind, timeOnly: timeOnly,
      );

  final String id;
  final String workerName;
  final String eventType;
  final DateTime confirmedAt;
  final String storagePath;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;

  final String? gpsStatus;
  final String? photoStatus;
  final String? capturedAddress;
  final DateTime? photoCapturedAt;
  final DateTime? gpsCapturedAt;
  final DateTime? photoObservedAt;
  final String storageBucket;
  final String? stopLabel, sourceClockInId, routeStopId, originKind;

  bool get hasLocation => latitude != null && longitude != null;
  final bool timeOnly;
  bool get isTimeOnly => storagePath.isEmpty && !hasLocation &&
      (timeOnly || ((photoStatus == null || photoStatus == 'not_required') &&
      (gpsStatus == null || gpsStatus == 'not_required')));
  String get eventLabel => switch (eventType) {
    'route_arrival' => '現場到着',
    'route_move' => '現場移動',
    'route_stop' => '途中現場',
    'clock_out' => '退勤',
    _ => '出勤',
  };
  String get missingPhotoLabel => isTimeOnly ? '時刻のみの記録' : '写真未登録・送信失敗';
}

class DailyReportRepository {
  DailyReportRepository._(this._client);

  final SupabaseClient _client;

  static DailyReportRepository? maybeCreate() {
    if (!SupabaseBackend.isInitialized) return null;
    final client = SupabaseBackend.client;
    if (client.auth.currentUser == null) return null;
    return DailyReportRepository._(client);
  }

  Future<bool> vehicleMeterEnabled(String companyId) async {
    try {
      final value = await _client.rpc('get_attendance_rollout_capabilities', params: {'p_company_id': companyId});
      return value is Map && value['version'] == 1 && value['company_id'] == companyId && value['vehicle_meter_enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> vehicleMeterEnabledForAnchor(String? anchor) async {
    if (anchor == null) {
      return false;
    }
    try {
      final row = await _client.from('attendance_verifications').select('company_id').eq('id', anchor).maybeSingle();
      final company = row?['company_id']?.toString();
      return company != null && await vehicleMeterEnabled(company);
    } catch (_) {
      return false;
    }
  }

  Future<List<VehicleReportSnapshot>> _vehicleReportContext(String reportId, DateTime date) async {
    final value = await _client.rpc('get_report_vehicle_meter_context', params: {'p_report_id': reportId});
    return parseVehicleReportContext(value, _dbDate(date));
  }

  void _applyMeterSnapshots(List<DailyReportWorkerDraft> workers, List<VehicleReportSnapshot> snapshots) {
    for (final snapshot in snapshots) {
      final matches = workers.where((worker) => worker.workerId == snapshot.workerId).toList();
      if (matches.length != 1) {
        throw StateError('車両の運転手が日報メンバーと一致しません');
      }
      final worker = matches.single;
      worker.meterManaged = true;
      worker.meterSourceClockInId = snapshot.sourceId;
      worker.meterEventId = snapshot.eventId;
      worker.vehicleId = snapshot.vehicleId;
      worker.vehicleName = snapshot.vehicleName;
      worker.previousOdometerKm = snapshot.previousKm;
      worker.odometerKm = snapshot.currentKm;
      worker.tripDistanceKm = snapshot.distanceKm;
    }
  }

  Future<List<DailyReportSiteGroup>> loadClockedInGroups(DateTime date) async {
    final rows = await _client.rpc(
      'daily_report_clocked_in_destinations',
      params: {'p_date': _dbDate(date)},
    );

    final byDestination = <String, _SiteGroupDraft>{};

    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final siteId = row['site_id']?.toString();
      final routeId = row['route_assignment_id']?.toString();
      final workerId = row['worker_id']?.toString() ?? '';
      final destinationId = row['destination_id']?.toString() ?? '';
      if (destinationId.isEmpty || workerId.isEmpty) continue;

      final key = siteId != null && siteId.isNotEmpty
          ? 'site:$siteId'
          : 'route:$routeId';
      final group = byDestination.putIfAbsent(
        key,
        () => _SiteGroupDraft(
          siteId: siteId?.isEmpty == true ? null : siteId,
          routeAssignmentId: routeId?.isEmpty == true ? null : routeId,
          siteName: row['destination_name']?.toString() ?? '',
        ),
      );
      group.workers.add(
        DailyReportWorkerDraft(
          workerId: workerId,
          workerName: row['worker_name']?.toString() ?? '',
        ),
      );
    }

    final workerIds = byDestination.values
        .expand((group) => group.workers)
        .map((worker) => worker.workerId)
        .toSet()
        .toList();

    if (workerIds.isNotEmpty) {
      final selections = await _client
          .from('work_vehicle_route_selections')
          .select(
            'worker_id,vehicle_id,route_assignment_id,'
            'vehicles(display_name,odometer_km),'
            'route_assignments(route_name)',
          )
          .eq('work_date', _dbDate(date))
          .inFilter('worker_id', workerIds);

      final start = DateTime(date.year, date.month, date.day);
      final end = DateTime(date.year, date.month, date.day + 1);
      final starts = await _client
          .from('attendance_verifications')
          .select(
            'worker_id,event_type,confirmed_at,work_date,site_id,route_assignment_id,vehicle_id,'
            'vehicles(display_name,odometer_km),route_assignments(route_name)',
          )
          .eq('event_type', 'clock_in')
          .inFilter('worker_id', workerIds)
          .or('work_date.eq.${_dbDate(date)},and(work_date.is.null,confirmed_at.gte.${start.toUtc().toIso8601String()},confirmed_at.lt.${end.toUtc().toIso8601String()})')
          .order('confirmed_at');

      final byWorker = <String, Map<String, dynamic>>{
        for (final raw in selections)
          raw['worker_id'].toString(): Map<String, dynamic>.from(raw),
      };

      for (final group in byDestination.values) {
        for (final worker in group.workers) {
          final snapshot = dailyReportClockInSnapshot(
            starts, workerId: worker.workerId, workDate: date,
            siteId: group.siteId, routeId: group.routeAssignmentId,
          );
          final selection = snapshot ?? byWorker[worker.workerId];
          if (selection == null) continue;
          final vehicle = selection['vehicles'];
          final route = selection['route_assignments'];
          worker.vehicleId = selection['vehicle_id']?.toString();
          worker.routeId = selection['route_assignment_id']?.toString();
          if (vehicle is Map) {
            worker.vehicleName = vehicle['display_name']?.toString();
            worker.odometerKm =
                (vehicle['odometer_km'] as num?)?.toDouble();
          }
          if (route is Map) {
            worker.routeName = route['route_name']?.toString();
          }
        }
      }
    }

    return byDestination.values
        .map(
          (group) => DailyReportSiteGroup(
            siteId: group.siteId,
            routeAssignmentId: group.routeAssignmentId,
            siteName: group.siteName,
            workers: group.workers,
          ),
        )
        .toList();
  }

  Future<DailyReportRecord?> loadReport({
    required DateTime date,
    String? siteId,
    String? routeAssignmentId,
    String? vehicleClockInAnchorId,
  }) async {
    var query = _client
        .from('daily_reports')
        .select(
          'id, company_id, created_by, updated_by, site_id, route_assignment_id, report_date, work_description, status, signer_name, signature_json, representative_signer_name, representative_signature_json, supervisor_signer_name, supervisor_signature_json, signed_at, sites(name), route_assignments(route_name), daily_report_workers(worker_id, overtime_hours, early_hours, night_hours, allowance_amount, allowance_label, vehicle_id, route_assignment_id, odometer_km, workers(name), vehicles(display_name), route_assignments(route_name))',
        )
        .eq('report_date', _dbDate(date));
    query = siteId != null
        ? query.eq('site_id', siteId)
        : query.eq('route_assignment_id', routeAssignmentId!);
    final rows = await query.limit(1);

    if (rows.isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first);
    final site = row['sites'];
    final route = row['route_assignments'];
    final rawWorkers = row['daily_report_workers'];
    final meterEnabled = await vehicleMeterEnabled(row['company_id']?.toString() ?? '');
    final storedMeters = <String, Map<String, dynamic>>{};
    if (meterEnabled) {
      final details = await _client.from('daily_report_workers').select(
        'worker_id,vehicle_meter_event_id,vehicle_meter_source_clock_in_id,previous_odometer_km,trip_distance_km')
        .eq('report_id', row['id']);
      for (final detail in details) {
        storedMeters[detail['worker_id'].toString()] = Map<String, dynamic>.from(detail);
      }
    }

    final workers = <DailyReportWorkerDraft>[];
    if (rawWorkers is List) {
      for (final raw in rawWorkers) {
        final detail = Map<String, dynamic>.from(raw as Map);
        detail.addAll(storedMeters[detail['worker_id']?.toString()] ?? const {});
        final worker = detail['workers'];
        workers.add(
          DailyReportWorkerDraft(
            workerId: detail['worker_id']?.toString() ?? '',
            workerName: worker is Map ? worker['name']?.toString() ?? '' : '',
            overtimeHours: _number(detail['overtime_hours']),
            earlyHours: _number(detail['early_hours']),
            nightHours: _number(detail['night_hours']),
            allowanceAmount:
                (detail['allowance_amount'] as num?)?.toInt() ?? 0,
            allowanceLabel: detail['allowance_label']?.toString() ?? '',
            vehicleId: detail['vehicle_id']?.toString(),
            vehicleName: detail['vehicles'] is Map
                ? detail['vehicles']['display_name']?.toString()
                : null,
            routeId: detail['route_assignment_id']?.toString(),
            routeName: detail['route_assignments'] is Map
                ? detail['route_assignments']['route_name']?.toString()
                : null,
            odometerKm: (detail['odometer_km'] as num?)?.toDouble(),
            meterManaged: detail['vehicle_meter_event_id'] != null,
            meterEventId: detail['vehicle_meter_event_id']?.toString(),
            meterSourceClockInId: detail['vehicle_meter_source_clock_in_id']?.toString(),
            previousOdometerKm: detail['previous_odometer_km'] == null ? null : _number(detail['previous_odometer_km']),
            tripDistanceKm: detail['trip_distance_km'] == null ? null : _number(detail['trip_distance_km']),
          ),
        );
      }
    }

    if (meterEnabled && row['route_assignment_id'] != null) {
      for (final worker in workers) {
        worker.routeId ??= row['route_assignment_id'].toString();
        worker.routeName ??= route is Map ? route['route_name']?.toString() : null;
      }
    }

    if (meterEnabled && vehicleClockInAnchorId != null && row['status'] != 'signed' &&
        (row['created_by'] == _client.auth.currentUser?.id || row['updated_by'] == _client.auth.currentUser?.id)) {
      _applyMeterSnapshots(workers, await _vehicleReportContext(row['id'].toString(), date));
    }

    return DailyReportRecord(
      id: row['id']?.toString() ?? '',
      notificationRetryScope: savedReportNotificationScopeFromRow(row, notificationRetryUserId),
      siteId: row['site_id']?.toString(),
      routeAssignmentId: row['route_assignment_id']?.toString(),
      siteName: site is Map
          ? site['name']?.toString() ?? ''
          : route is Map
              ? route['route_name']?.toString() ?? ''
              : '',
      date: DateTime.tryParse(row['report_date']?.toString() ?? '') ?? date,
      workDescription: row['work_description']?.toString() ?? '',
      status: row['status']?.toString() ?? 'draft',
      signerName: row['signer_name']?.toString(),
      signatureJson: row['signature_json'],
      reporterSignerName: row['representative_signer_name']?.toString(),
      reporterSignatureJson: row['representative_signature_json'],
      responsibleSignerName:
          row['supervisor_signer_name']?.toString() ?? row['signer_name']?.toString(),
      responsibleSignatureJson:
          row['supervisor_signature_json'] ?? row['signature_json'],
      signedAt: DateTime.tryParse(row['signed_at']?.toString() ?? '')?.toLocal(),
      workers: workers,
    );
  }

  Future<List<DailyReportWorkerDraft>> loadAnchoredWorkers({
    required String anchorId, required DateTime workDate,
    required List<DailyReportWorkerDraft> existing,
    required List<DailyReportWorkerDraft> fallback,
    required bool allowNewMembers,
  }) async {
    final candidates = await GroupCheckoutRepository(_client).loadIfEnabled(anchorId, workDate);
    if (candidates == null) return existing;
    return mergeAnchoredGroupRoster(existing: existing, fallback: fallback,
      candidates: candidates, allowNewMembers: allowNewMembers);
  }

  Future<String> saveDraft({
    String? reportId,
    String? siteId,
    String? routeAssignmentId,
    required DateTime date,
    required String workDescription,
    required List<DailyReportWorkerDraft> workers,
    String? groupClockInAnchorId,
    String? vehicleClockInAnchorId,
  }) async {
    if (groupClockInAnchorId != null && workers.any((worker) => worker.sourceClockInId != null)) {
      final candidates = await GroupCheckoutRepository(_client).loadIfEnabled(groupClockInAnchorId, date);
      if (candidates == null) {
        throw StateError('現場メンバーの勤務を再確認してください');
      }
      final byWorker = {for (final row in candidates) row.workerId: row.sourceId};
      if (workers.any((worker) => worker.sourceClockInId != null &&
          byWorker[worker.workerId] != worker.sourceClockInId)) {
        throw StateError('対象勤務が変わりました。日報を再読み込みしてください');
      }
    }
    final meterEnabled = await vehicleMeterEnabledForAnchor(vehicleClockInAnchorId);
    if (!meterEnabled && workers.any((worker) => worker.meterManaged)) {
      throw StateError('車両の勤務記録を再確認してください');
    }
    final value = await _client.rpc(
      'save_daily_report_destination_draft',
      params: {
        'p_report_id': reportId,
        'p_site_id': siteId,
        'p_route_assignment_id': routeAssignmentId,
        'p_report_date': _dbDate(date),
        'p_work_description': workDescription.trim(),
        'p_workers': workers.map((worker) => worker.toRpcJson()).toList(),
      },
    );

    final id = value?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('日報IDを確認できません。');
    }

    if (meterEnabled) {
      final snapshots = await _vehicleReportContext(id, date);
      _applyMeterSnapshots(workers, snapshots);
      for (final snapshot in snapshots.where((snapshot) => snapshot.hasEvent)) {
        final attached = await _client.rpc('attach_vehicle_meter_to_report', params: {
          'p_report_id': id, 'p_source_clock_in_id': snapshot.sourceId,
        });
        if (attached is! Map || attached['attached'] != true || attached['has_claim'] != true || attached['has_event'] != true ||
            attached['previous_km'] == null || attached['current_km'] == null || attached['distance_km'] == null ||
            attached['source_clock_in_id'] != snapshot.sourceId ||
            attached['event_id'] != snapshot.eventId ||
            attached['worker_id'] != snapshot.workerId || attached['vehicle_id'] != snapshot.vehicleId ||
            attached['work_date'] != _dbDate(date) ||
            _number(attached['previous_km']) != snapshot.previousKm ||
            _number(attached['current_km']) != snapshot.currentKm ||
            _number(attached['distance_km']) != snapshot.distanceKm) {
          throw StateError('日報の車両距離の連携を再確認してください');
        }
      }
    } else {
      for (final worker in workers) {
        await _client.rpc(
          'save_daily_report_vehicle_usage',
          params: {
            'p_report_id': id,
            'p_worker_id': worker.workerId,
            'p_vehicle_id': worker.vehicleId,
            'p_route_assignment_id': worker.routeId,
            'p_odometer_km': worker.odometerKm,
          },
        );
      }
    }

    await _client.rpc(
      'link_daily_report_attendance_evidence',
      params: {'p_report_id': id},
    );

    final groupSources = workers.where((worker) => worker.sourceClockOutAt != null)
      .map((worker) => worker.sourceClockInId)
      .whereType<String>().toSet().toList()..sort();
    if (groupClockInAnchorId != null && groupSources.isNotEmpty) {
      final attachment = await _client.rpc('attach_group_report_sources', params: {
        'p_daily_report_id': id,
        'p_anchor_source_clock_in_id': groupClockInAnchorId,
        'p_source_clock_in_ids': groupSources,
      });
      if (!groupReportSourcesAttached(attachment, id, groupSources)) {
        throw StateError('日報は保存済みですが勤務証跡の連携が未確認です。同じ日報を再保存してください');
      }
    }

    if (routeAssignmentId != null) {
      try {
        await _client.rpc('link_route_journey_report', params: {'p_report_id': id});
      } on PostgrestException catch (error) {
        if (error.code != 'PGRST202' && error.code != '42883') rethrow;
        // New staged migration is optional while OFF; no legacy data changes.
      }
    }

    return id;
  }

  String? get notificationRetryUserId => _client.auth.currentUser?.id;

  Future<void> verifySavedNotificationScope(SavedReportNotificationRetry retry) async {
    if (notificationRetryUserId != retry.userId) throw StateError('日報通知の利用者が変更されています');
    final row = await _client.from('daily_reports').select('id,company_id,updated_by')
      .eq('id', retry.reportId).eq('company_id', retry.companyId)
      .eq('updated_by', retry.userId).maybeSingle();
    if (row == null || row['id'] != retry.reportId || row['company_id'] != retry.companyId ||
        row['updated_by'] != retry.userId) {
      throw StateError('登録済み日報を確認できません');
    }
  }

  /// The server owns rollout gating, recipient selection and durable deduplication.
  /// A missing staged RPC is unavailable, not evidence that notifications were sent.
  Future<bool> publishSavedGroupReportNotifications(String reportId) async {
    return publishSavedGroupReport(reportId, invoke: (id) =>
      _client.rpc('publish_saved_group_report_notifications',
        params: {'p_report_id': id}));
  }

  Future<void> sign({
    required String reportId,
    required String signerName,
    required Object signatureJson,
  }) async {
    await _client.rpc(
      'save_daily_report_signature',
      params: {
        'p_report_id': reportId,
        'p_role': 'supervisor',
        'p_signer_name': signerName.trim(),
        'p_signature_json': {'strokes': signatureJson},
      },
    );
  }

  Future<void> saveReporterSignature({
    required String reportId,
    required String signerName,
    required Object signatureJson,
  }) async {
    await _client.rpc(
      'save_daily_report_signature',
      params: {
        'p_report_id': reportId,
        'p_role': 'representative',
        'p_signer_name': signerName.trim(),
        'p_signature_json': {'strokes': signatureJson},
      },
    );
  }

  Future<List<DailyReportEvidenceRecord>> loadAttendanceEvidence({
    String? reportId,
    required DateTime date,
    String? siteId,
    String? routeAssignmentId,
  }) async {
    var captureEnabled = false;
    try {
      final user = _client.auth.currentUser;
      if (user == null) { throw StateError('ログインが必要です'); }
      final memberships = await _client.from('company_members').select('company_id')
        .eq('user_id', user.id).limit(1);
      if (memberships.isEmpty) { throw StateError('会社情報がありません'); }
      final companyId = memberships.first['company_id'] as String;
      final capability = await _client.rpc('get_attendance_capture_capability',
        params: {'p_company_id': companyId});
      captureEnabled = capability is Map && capability['version'] == 1 &&
        capability['company_id'] == companyId && capability['capture_enabled'] == true;
    } catch (_) {
      captureEnabled = false;
    }
    var query = _client.from('attendance_verifications').select(
      'id,event_type,verification_mode,confirmed_at,source_clock_in_id,photo_storage_path,latitude,longitude,accuracy_m,workers(name),sites(name)'
      '${captureEnabled ? ',capture_contract_version,gps_capture_status,photo_capture_status,gps_captured_at,photo_captured_at,photo_observed_at,captured_address' : ''}');
    query = siteId != null
        ? query.eq('site_id', siteId)
        : query.eq('route_assignment_id', routeAssignmentId!);

    if (reportId != null && reportId.isNotEmpty) {
      query = query.eq('daily_report_id', reportId);
    } else {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .or('work_date.eq.${_dbDate(date)},and(work_date.is.null,confirmed_at.gte.${start.toUtc().toIso8601String()},confirmed_at.lt.${end.toUtc().toIso8601String()})');
    }

    final rows = await query.order('confirmed_at');
    final evidence = <DailyReportEvidenceRecord>[
      for (final raw in rows)
          DailyReportEvidenceRecord(
            id: raw['id']?.toString() ?? '',
            workerName: raw['workers'] is Map
                ? raw['workers']['name']?.toString() ?? ''
                : '',
            eventType: raw['event_type']?.toString() ?? '',
            confirmedAt:
                DateTime.tryParse(raw['confirmed_at']?.toString() ?? '')
                        ?.toLocal() ??
                    DateTime.fromMillisecondsSinceEpoch(0),
            timeOnly: raw['verification_mode'] == 'manual',
            storagePath: raw['photo_storage_path']?.toString() ?? '',
            gpsStatus: raw['gps_capture_status']?.toString(),
            photoStatus: raw['photo_capture_status']?.toString(),
            capturedAddress: raw['captured_address']?.toString(),
            gpsCapturedAt: DateTime.tryParse(raw['gps_captured_at']?.toString() ?? '')?.toLocal(),
            photoCapturedAt: DateTime.tryParse(raw['photo_captured_at']?.toString() ?? '')?.toLocal(),
            photoObservedAt: DateTime.tryParse(raw['photo_observed_at']?.toString() ?? '')?.toLocal(),
            stopLabel: raw['sites'] is Map ? raw['sites']['name']?.toString() : null,
            sourceClockInId: raw['source_clock_in_id']?.toString(),
            latitude: (raw['latitude'] as num?)?.toDouble(),
            longitude: (raw['longitude'] as num?)?.toDouble(),
            accuracyM: (raw['accuracy_m'] as num?)?.toDouble(),
          ),
    ];
    if (routeAssignmentId != null && reportId != null && reportId.isNotEmpty) {
      try {
        final value = await _client.rpc('route_journey_report_evidence', params: {'p_report_id': reportId});
        if (value is! List) throw StateError('途中現場の証跡を確認できません');
        for (final row in value) {
          if (row is! Map || row['payload'] is! Map || row['route_assignment_id'] != routeAssignmentId ||
              row['daily_report_id'] != reportId || row['work_date'] != _dbDate(date)) {
            throw StateError('途中現場の証跡が対象日報と一致しません');
          }
          final raw = row['payload'] as Map;
          final recorded = DateTime.tryParse(raw['attempted_at']?.toString() ?? '') ??
            DateTime.tryParse(row['recorded_at']?.toString() ?? '');
          if (recorded == null) throw StateError('途中現場の記録時刻を確認できません');
          evidence.add(DailyReportEvidenceRecord(id: row['id'] as String,
            workerName: row['worker_name']?.toString() ?? '',
            eventType: row['visit_kind'] == 'end' ? 'route_move' :
              row['visit_kind'] == 'start' ? 'route_arrival' : 'route_stop',
            confirmedAt: recorded.toLocal(), storagePath: raw['photo_storage_path']?.toString() ?? '',
            timeOnly: row['visit_kind'] == 'end' || row['verification_mode'] == 'manual',
            storageBucket: 'attendance-route-evidence', stopLabel: row['stop_label']?.toString(),
            sourceClockInId: row['source_clock_in_id']?.toString(), routeStopId: row['route_stop_id']?.toString(),
            originKind: row['origin_kind']?.toString(), gpsStatus: raw['gps_capture_status']?.toString(),
            photoStatus: raw['photo_capture_status']?.toString(), capturedAddress: raw['captured_address']?.toString(),
            gpsCapturedAt: DateTime.tryParse(raw['gps_captured_at']?.toString() ?? '')?.toLocal(),
            photoCapturedAt: DateTime.tryParse(raw['photo_captured_at']?.toString() ?? '')?.toLocal(),
            photoObservedAt: DateTime.tryParse(raw['photo_observed_at']?.toString() ?? '')?.toLocal(),
            latitude: (raw['latitude'] as num?)?.toDouble(), longitude: (raw['longitude'] as num?)?.toDouble(),
            accuracyM: (raw['accuracy_m'] as num?)?.toDouble()));
        }
      } on PostgrestException catch (error) {
        if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      }
    }
    evidence.sort((a, b) {
      final byTime = a.confirmedAt.compareTo(b.confirmedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    final addresses = DailyReportEvidenceAddressResolver(
      reverseGeocode: const AttendanceCaptureMetadataService().reverseGeocodeCapturedLocation,
    );
    // Enrich display/PDF only; never rewrite stored attendance or substitute
    // the company/site address for the recorded GPS location.
    return Future.wait(evidence.map((record) async => record.withCapturedAddress(
      await addresses.resolve(
        savedAddress: record.capturedAddress,
        latitude: record.latitude, longitude: record.longitude,
        gpsStatus: record.gpsStatus,
        timeOnly: record.timeOnly || record.isTimeOnly,
      ),
    )));
  }

  Future<List<DailyReportPdfEvidence>> loadPdfEvidence(List<DailyReportEvidenceRecord> records) async {
    final attachments = <DailyReportPdfEvidence>[];
    for (final record in records) {
      if (record.storagePath.isEmpty) {
        attachments.add(DailyReportPdfEvidence(record: record));
        continue;
      }
      try {
        final bytes = await _client.storage.from(record.storageBucket)
          .download(record.storagePath).timeout(const Duration(seconds: 15));
        attachments.add(DailyReportPdfEvidence(record: record, photoBytes: bytes));
      } catch (_) {
        attachments.add(DailyReportPdfEvidence(record: record, downloadFailed: true));
      }
    }
    return attachments;
  }

  Future<String> attendanceEvidenceUrl(String path, {String bucket = 'attendance-evidence'}) {
    return _client.storage
        .from(bucket)
        .createSignedUrl(path, 3600);
  }

  Future<String> requestEdit({
    required String reportId,
    String? reason,
  }) async {
    final value = await _client.rpc(
      'request_daily_report_edit',
      params: {
        'p_report_id': reportId,
        'p_reason': reason?.trim(),
      },
    );
    return value?.toString() ?? '';
  }

  /// A notification opens only its exact request, including resolved requests.
  /// Ordinary approval lists remain pending-only; existing SELECT RLS applies.
  Future<List<Map<String, dynamic>>> loadPendingApprovals({
    String? requestId,
  }) async {
    final query = _client
        .from('daily_report_edit_requests')
        .select(
          'id, report_id, reason, status, created_at, requested_by, daily_reports(report_date, sites(name))',
        );
    final rows = await (requestId == null
        ? query.eq('status', 'pending')
        : query.eq('id', requestId)).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> decideEdit({
    required String requestId,
    required bool approve,
  }) async {
    final value = await _client.rpc(
      'decide_daily_report_edit',
      params: {
        'p_request_id': requestId,
        'p_decision': approve ? 'approve' : 'reject',
      },
    );
    return value?.toString() ?? '';
  }

  String _dbDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static double _number(Object? value) =>
      (value as num?)?.toDouble() ??
      double.tryParse(value?.toString() ?? '') ??
      0;
}

class _SiteGroupDraft {
  _SiteGroupDraft({
    required this.siteName,
    this.siteId,
    this.routeAssignmentId,
  });

  final String? siteId;
  final String? routeAssignmentId;
  final String siteName;
  final List<DailyReportWorkerDraft> workers = [];
}


bool groupReportSourcesAttached(Object? value, String reportId, List<String> sourceIds) {
  if (value is! Map || value['daily_report_id'] != reportId || value['source_clock_in_ids'] is! List) {
    return false;
  }
  final rows = value['source_clock_in_ids'] as List;
  if (rows.any((row) => row is! String)) {
    return false;
  }
  final sources = rows.cast<String>().toList()..sort();
  final expected = sourceIds.toList()..sort();
  return sources.length == expected.length &&
    List.generate(sources.length, (i) => sources[i] == expected[i]).every((same) => same);
}
