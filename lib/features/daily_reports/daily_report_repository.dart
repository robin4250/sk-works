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
  });

  final String workerId;
  final String workerName;
  double overtimeHours;
  double earlyHours;
  double nightHours;
  int allowanceAmount;
  String allowanceLabel;

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
    required this.siteId,
    required this.siteName,
    required this.workers,
  });

  final String siteId;
  final String siteName;
  final List<DailyReportWorkerDraft> workers;
}

class DailyReportRecord {
  const DailyReportRecord({
    required this.id,
    required this.siteId,
    required this.siteName,
    required this.date,
    required this.workDescription,
    required this.status,
    required this.workers,
    this.signerName,
    this.signatureJson,
    this.signedAt,
  });

  final String id;
  final String siteId;
  final String siteName;
  final DateTime date;
  final String workDescription;
  final String status;
  final List<DailyReportWorkerDraft> workers;
  final String? signerName;
  final Object? signatureJson;
  final DateTime? signedAt;

  bool get signed => status == 'signed';
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
      'daily_report_clocked_in_workers',
      params: {'p_date': _dbDate(date)},
    );

    final bySite = <String, _SiteGroupDraft>{};

    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final siteId = row['site_id']?.toString() ?? '';
      final workerId = row['worker_id']?.toString() ?? '';
      if (siteId.isEmpty || workerId.isEmpty) continue;

      final group = bySite.putIfAbsent(
        siteId,
        () => _SiteGroupDraft(
          siteId: siteId,
          siteName: row['site_name']?.toString() ?? '',
        ),
      );
      group.workers.add(
        DailyReportWorkerDraft(
          workerId: workerId,
          workerName: row['worker_name']?.toString() ?? '',
        ),
      );
    }

    return bySite.values
        .map(
          (group) => DailyReportSiteGroup(
            siteId: group.siteId,
            siteName: group.siteName,
            workers: group.workers,
          ),
        )
        .toList();
  }

  Future<DailyReportRecord?> loadReport({
    required DateTime date,
    required String siteId,
  }) async {
    final rows = await _client
        .from('daily_reports')
        .select(
          'id, site_id, report_date, work_description, status, signer_name, signature_json, signed_at, sites(name), daily_report_workers(worker_id, overtime_hours, early_hours, night_hours, allowance_amount, allowance_label, workers(name))',
        )
        .eq('site_id', siteId)
        .eq('report_date', _dbDate(date))
        .limit(1);

    if (rows.isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first);
    final site = row['sites'];
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
          ),
        );
      }
    }

    return DailyReportRecord(
      id: row['id']?.toString() ?? '',
      siteId: row['site_id']?.toString() ?? siteId,
      siteName: site is Map ? site['name']?.toString() ?? '' : '',
      date: DateTime.tryParse(row['report_date']?.toString() ?? '') ?? date,
      workDescription: row['work_description']?.toString() ?? '',
      status: row['status']?.toString() ?? 'draft',
      signerName: row['signer_name']?.toString(),
      signatureJson: row['signature_json'],
      signedAt: DateTime.tryParse(row['signed_at']?.toString() ?? '')?.toLocal(),
      workers: workers,
    );
  }

  Future<String> saveDraft({
    String? reportId,
    required String siteId,
    required DateTime date,
    required String workDescription,
    required List<DailyReportWorkerDraft> workers,
  }) async {
    final value = await _client.rpc(
      'save_daily_report_draft',
      params: {
        'p_report_id': reportId,
        'p_site_id': siteId,
        'p_report_date': _dbDate(date),
        'p_work_description': workDescription.trim(),
        'p_workers': workers.map((worker) => worker.toRpcJson()).toList(),
      },
    );

    final id = value?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('日報IDを確認できません。');
    }
    return id;
  }

  Future<void> sign({
    required String reportId,
    required String signerName,
    required Object signatureJson,
  }) async {
    await _client.rpc(
      'sign_daily_report',
      params: {
        'p_report_id': reportId,
        'p_signer_name': signerName.trim(),
        'p_signature_json': signatureJson,
      },
    );
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

  Future<List<Map<String, dynamic>>> loadPendingApprovals() async {
    final rows = await _client
        .from('daily_report_edit_requests')
        .select(
          'id, report_id, reason, status, created_at, requested_by, daily_reports(report_date, sites(name))',
        )
        .eq('status', 'pending')
        .order('created_at', ascending: false);
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
    required this.siteId,
    required this.siteName,
  });

  final String siteId;
  final String siteName;
  final List<DailyReportWorkerDraft> workers = [];
}
