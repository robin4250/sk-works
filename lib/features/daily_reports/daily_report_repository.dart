import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';

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
  });

  final String id;
  final String workerName;
  final String eventType;
  final DateTime confirmedAt;
  final String storagePath;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;

  bool get hasLocation => latitude != null && longitude != null;
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

      final byWorker = <String, Map<String, dynamic>>{
        for (final raw in selections)
          raw['worker_id'].toString(): Map<String, dynamic>.from(raw),
      };

      for (final group in byDestination.values) {
        for (final worker in group.workers) {
          final selection = byWorker[worker.workerId];
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
  }) async {
    var query = _client
        .from('daily_reports')
        .select(
          'id, site_id, route_assignment_id, report_date, work_description, status, signer_name, signature_json, representative_signer_name, representative_signature_json, supervisor_signer_name, supervisor_signature_json, signed_at, sites(name), route_assignments(route_name), daily_report_workers(worker_id, overtime_hours, early_hours, night_hours, allowance_amount, allowance_label, vehicle_id, route_assignment_id, odometer_km, workers(name), vehicles(display_name), route_assignments(route_name))',
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

    final workers = <DailyReportWorkerDraft>[];
    if (rawWorkers is List) {
      for (final raw in rawWorkers) {
        final detail = Map<String, dynamic>.from(raw as Map);
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
          ),
        );
      }
    }

    return DailyReportRecord(
      id: row['id']?.toString() ?? '',
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

  Future<String> saveDraft({
    String? reportId,
    String? siteId,
    String? routeAssignmentId,
    required DateTime date,
    required String workDescription,
    required List<DailyReportWorkerDraft> workers,
  }) async {
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

    await _client.rpc(
      'link_daily_report_attendance_evidence',
      params: {'p_report_id': id},
    );

    return id;
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
    var query = _client
        .from('attendance_verifications')
        .select(
          'id,event_type,confirmed_at,photo_storage_path,latitude,longitude,accuracy_m,workers(name)',
        )
        .not('photo_storage_path', 'is', null);
    query = siteId != null
        ? query.eq('site_id', siteId)
        : query.eq('route_assignment_id', routeAssignmentId!);

    if (reportId != null && reportId.isNotEmpty) {
      query = query.eq('daily_report_id', reportId);
    } else {
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .gte('confirmed_at', start.toUtc().toIso8601String())
          .lt('confirmed_at', end.toUtc().toIso8601String());
    }

    final rows = await query.order('confirmed_at');
    return [
      for (final raw in rows)
        if ((raw['photo_storage_path']?.toString() ?? '').isNotEmpty)
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
            storagePath: raw['photo_storage_path'].toString(),
            latitude: (raw['latitude'] as num?)?.toDouble(),
            longitude: (raw['longitude'] as num?)?.toDouble(),
            accuracyM: (raw['accuracy_m'] as num?)?.toDouble(),
          ),
    ];
  }

  Future<String> attendanceEvidenceUrl(String path) {
    return _client.storage
        .from('attendance-evidence')
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
