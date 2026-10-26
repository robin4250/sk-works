import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'daily_report_pdf_evidence.dart';
import 'daily_report_repository.dart';
import 'route_visit_report_context.dart';

enum DailyReportSaveState { saved, supervisorPending, finalizationPending, inputPending }

extension DailyReportSaveStateLabel on DailyReportSaveState {
  String get label => switch (this) {
    DailyReportSaveState.saved => '保存済み',
    DailyReportSaveState.supervisorPending => 'サイン待ち',
    DailyReportSaveState.finalizationPending => '確定待ち',
    DailyReportSaveState.inputPending => '入力途中',
  };
}

class DailyReportSiteHistoryResult {
  const DailyReportSiteHistoryResult(this.entries, {this.complete = true, this.warning});
  final List<DailyReportMonthEntry> entries;
  final bool complete;
  final String? warning;
}

class DailyReportPendingResult {
  const DailyReportPendingResult(this.entries, {this.visitWarning});
  final List<DailyReportMonthEntry> entries;
  final String? visitWarning;
}

class DailyReportMonthEntry {
  const DailyReportMonthEntry({
    required this.id,
    required this.date,
    required this.name,
    required this.status,
    this.siteId,
    this.routeId,
    this.visitContext,
    this.createdAt,
    this.reporterSigned = false,
    this.supervisorSigned = false,
  });
  final String id, name, status;
  final DateTime date;
  final String? siteId, routeId;
  final RouteVisitReportContext? visitContext;
  final DateTime? createdAt;
  final bool reporterSigned, supervisorSigned;
  DailyReportSaveState get saveState {
    if (const ['signed', 'completed'].contains(status)) return DailyReportSaveState.saved;
    if (status == 'reporter_signed' || (status == 'draft' && reporterSigned && !supervisorSigned)) {
      return DailyReportSaveState.supervisorPending;
    }
    if (status == 'draft' && reporterSigned && supervisorSigned) return DailyReportSaveState.finalizationPending;
    return DailyReportSaveState.inputPending;
  }
  bool get isVisit => visitContext != null;
  String get kindLabel => isVisit ? '訪問日報' : routeId != null ? 'ルート日報' : '日報';
}

class DailyReportMonthDocument {
  const DailyReportMonthDocument(this.report, this.evidence);
  final DailyReportRecord report;
  final List<DailyReportPdfEvidence> evidence;
}

class DailyReportMonthRepository {
  DailyReportMonthRepository(this.client, this.reports);
  final SupabaseClient client;
  final DailyReportRepository reports;
  static DailyReportMonthRepository? maybeCreate() {
    final reports = DailyReportRepository.maybeCreate();
    return reports == null
        ? null
        : DailyReportMonthRepository(SupabaseBackend.client, reports);
  }

  String get actor {
    final user = client.auth.currentUser?.id;
    if (user == null) throw StateError('ログインを確認してください。');
    return user;
  }

  void checkActor(String user) {
    if (client.auth.currentUser?.id != user) {
      throw StateError('ログインが変更されました。画面を開き直してください。');
    }
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<DailyReportMonthEntry>> list(DateTime month, {String? workerId}) async {
    final user = actor;
    final result = <DailyReportMonthEntry>[];
    final reporterIds = await _signatureIds(month, workerId: workerId, reporter: true);
    final supervisorIds = await _signatureIds(month, workerId: workerId, reporter: false);
    // Explicit pagination avoids silently truncating a month's accessible reports.
    for (var offset = 0; ; offset += 500) {
      checkActor(user);
      var query = client
          .from('daily_reports')
          .select(
            'id,report_date,created_at,site_id,route_assignment_id,status,sites(name),route_assignments(route_name)${workerId == null ? '' : ',daily_report_workers!inner(worker_id)'}',
          )
          .gte('report_date', dateKey(DateTime(month.year, month.month)))
          .lt('report_date', dateKey(DateTime(month.year, month.month + 1)));
      if (workerId != null) query = query.eq('daily_report_workers.worker_id', workerId);
      final rows = await query
          .order('report_date')
          .order('id')
          .range(offset, offset + 499);
      checkActor(user);
      for (final row in rows) {
        final date = DateTime.tryParse(row['report_date']?.toString() ?? '');
        final id = row['id']?.toString();
        final site = row['site_id']?.toString();
        final route = row['route_assignment_id']?.toString();
        if (id == null || date == null || (site == null && route == null)) {
          throw StateError('日報の保存情報を確認できません。');
        }
        final destination = site != null
            ? row['sites']
            : row['route_assignments'];
        final name = destination is Map
            ? destination[site != null ? 'name' : 'route_name']?.toString()
            : null;
        if (name == null || name.isEmpty) throw StateError('日報の現場名を確認できません。');
        result.add(
          DailyReportMonthEntry(
            id: id,
            date: date,
            name: name,
            status: row['status']?.toString() ?? '',
            reporterSigned: reporterIds.contains(id), supervisorSigned: supervisorIds.contains(id),
            siteId: site,
            routeId: route,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
          ),
        );
      }
      if (rows.length < 500) break;
    }
    for (var offset = 0; ; offset += 500) {
      checkActor(user);
      final raw = await client.rpc('list_saved_route_visit_reports', params: {
        'p_from_date': dateKey(DateTime(month.year, month.month)),
        'p_until_date': dateKey(DateTime(month.year, month.month + 1)),
        'p_worker_id': workerId,
        'p_offset': offset,
        'p_limit': 500,
      });
      checkActor(user);
      if (raw is! List) throw StateError('訪問日報の一覧を確認できません。');
      for (final value in raw) {
        if (value is! Map) throw StateError('訪問日報の保存情報を確認できません。');
        String requiredText(String key) {
          final text = value[key]?.toString() ?? '';
          if (text.isEmpty) throw StateError('訪問日報の識別情報を確認できません。');
          return text;
        }
        final date = DateTime.tryParse(requiredText('report_date'));
        if (date == null || date.year != month.year || date.month != month.month) {
          throw StateError('訪問日報の日付を確認できません。');
        }
        final context = RouteVisitReportContext(
          sourceClockInId: requiredText('source_clock_in_id'),
          routeAssignmentId: requiredText('route_assignment_id'),
          routeStopId: requiredText('route_stop_id'),
          startCaptureId: requiredText('start_capture_id'),
          endCaptureId: requiredText('end_capture_id'),
        );
        context.toRpcParams();
        result.add(DailyReportMonthEntry(
          id: requiredText('id'), date: date,
          name: requiredText('site_name'), status: requiredText('status'),
          siteId: value['site_id']?.toString(),
          routeId: context.routeAssignmentId, visitContext: context,
          createdAt: DateTime.tryParse(value['created_at']?.toString() ?? ''),
        ));
      }
      if (raw.length < 500) break;
    }
    result.sort((a, b) {
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      if (a.isVisit != b.isVisit) return a.isVisit ? -1 : 1;
      final created = (a.createdAt ?? a.date).compareTo(b.createdAt ?? b.date);
      return created != 0 ? created : a.id.compareTo(b.id);
    });
    return result;
  }

  Future<Set<String>> _signatureIds(DateTime month, {String? workerId, required bool reporter}) async {
    final user = actor;
    final ids = <String>{};
    for (var offset = 0; ; offset += 500) {
      checkActor(user);
      var query = client.from('daily_reports').select('id${workerId == null ? '' : ',daily_report_workers!inner(worker_id)'}')
          .eq('status', 'draft').gte('report_date', dateKey(DateTime(month.year, month.month)))
          .lt('report_date', dateKey(DateTime(month.year, month.month + 1)));
      if (workerId != null) query = query.eq('daily_report_workers.worker_id', workerId);
      query = reporter ? query.not('representative_signature_json', 'is', null)
          : query.or('supervisor_signature_json.not.is.null,signature_json.not.is.null');
      final rows = await query.order('id').range(offset, offset + 499);
      checkActor(user);
      for (final row in rows) {
        final id = row['id'];
        if (id is! String || id.isEmpty || !ids.add(id)) throw StateError('署名状態を確認できません。');
      }
      if (rows.length < 500) return ids;
    }
  }

  /// All accessible supervisor-pending reports, independent of the selected month.
  /// Only saved metadata is fetched; signature stroke bodies are never selected.
  Future<DailyReportPendingResult> listPending({String? workerId}) async {
    final user = actor;
    final uuid = RegExp(r'^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$');
    if (workerId != null && !uuid.hasMatch(workerId)) throw StateError('対象メンバーを確認できません。');
    final result = <DailyReportMonthEntry>[];
    final seen = <String>{};
    DateTime? afterDate;
    String? afterId;
    for (;;) {
      checkActor(user);
      var query = client.from('daily_reports').select(
        'id,report_date,created_at,site_id,route_assignment_id,status,work_description,sites(name),route_assignments(route_name)${workerId == null ? '' : ',daily_report_workers!inner(worker_id)'}')
        .eq('status', 'draft').not('representative_signature_json', 'is', null)
        .isFilter('supervisor_signature_json', null).isFilter('signature_json', null);
      if (workerId != null) query = query.eq('daily_report_workers.worker_id', workerId);
      if (afterDate != null) query = query.or('report_date.gt.${dateKey(afterDate)},and(report_date.eq.${dateKey(afterDate)},id.gt.$afterId)');
      final rows = await query.order('report_date').order('id').range(0, 199);
      checkActor(user);
      for (final row in rows) {
        final id = row['id'];
        final date = DateTime.tryParse(row['report_date']?.toString() ?? '');
        final site = row['site_id'] as String?, route = row['route_assignment_id'] as String?;
        final destination = site != null ? row['sites'] : row['route_assignments'];
        final name = destination is Map ? destination[site != null ? 'name' : 'route_name'] : null;
        if (id is! String || !uuid.hasMatch(id) || date == null || row['status'] != 'draft' || (site == null && route == null) ||
            name is! String || name.trim().isEmpty || !seen.add('report:$id') ||
            (afterDate != null && (date.isBefore(afterDate) || (date == afterDate && id.compareTo(afterId!) <= 0)))) {
          throw StateError('サイン待ちの日報を確認できません。');
        }
        // Missing required report input must not be represented as supervisor-only waiting.
        if (row['work_description'] is String && (row['work_description'] as String).trim().isNotEmpty) {
          result.add(DailyReportMonthEntry(id: id, date: date, name: name, status: 'draft',
            siteId: site, routeId: route, reporterSigned: true,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')));
        }
        afterDate = date; afterId = id;
      }
      if (rows.length < 200) break;
    }
    String? warning;
    try {
      final companies = await client.from('company_members').select('company_id').eq('user_id', user).order('company_id');
      checkActor(user);
      final companyIds = <String>{};
      for (final company in companies) {
        final companyId = company['company_id'];
        if (companyId is! String || !uuid.hasMatch(companyId) || !companyIds.add(companyId)) throw StateError('会社を確認できません。');
        DateTime? cursorDate; String? cursorId;
        for (;;) {
          final raw = await client.rpc('list_pending_route_visit_reports', params: {
            'p_company_id': companyId, 'p_worker_id': workerId,
            'p_after_date': cursorDate == null ? null : dateKey(cursorDate), 'p_after_id': cursorId, 'p_limit': 200,
          });
          checkActor(user);
          if (raw is! Map || raw['actor_id'] != user || raw['company_id'] != companyId || raw['entries'] is! List) {
            throw StateError('訪問日報の対象を確認できません。');
          }
          final page = raw['entries'] as List;
          if (page.length > 200) throw StateError('訪問日報の件数を確認できません。');
          for (final row in page) {
            if (row is! Map || row['company_id'] != companyId || row['status'] != 'reporter_signed' ||
                row['reporter_signed'] != true || row['supervisor_signed'] != false) { throw StateError('訪問日報の署名状態を確認できません。'); }
            String text(String key) {
              final value = row[key]; if (value is! String || value.isEmpty) throw StateError('訪問日報の識別情報を確認できません。');return value;
            }
            final id = text('id'), date = DateTime.tryParse(text('report_date'));
            if (date == null || !seen.add('visit:$id') || (cursorDate != null &&
                (date.isBefore(cursorDate) || (date == cursorDate && id.compareTo(cursorId!) <= 0)))) { throw StateError('訪問日報の順序を確認できません。'); }
            final context = RouteVisitReportContext(sourceClockInId: text('source_clock_in_id'),
              routeAssignmentId: text('route_assignment_id'), routeStopId: text('route_stop_id'),
              startCaptureId: text('start_capture_id'), endCaptureId: text('end_capture_id'));
            context.toRpcParams();
            result.add(DailyReportMonthEntry(id: id, date: date, name: text('site_name'), status: 'reporter_signed',
              siteId: row['site_id'] is String ? row['site_id'] as String : null, routeId: context.routeAssignmentId, visitContext: context, reporterSigned: true,
              createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')));
            cursorDate = date; cursorId = id;
          }
          if (page.length < 200) break;
        }
      }
    } catch (_) {
      checkActor(user);
      // Partial visit pages are never presented as a complete list.
      result.removeWhere((entry) => entry.isVisit);
      warning = '訪問日報のサイン待ちは未確認です。再読み込みしてください。';
    }
    checkActor(user);
    result.sort((a, b) { final name = a.name.compareTo(b.name); return name != 0 ? name : a.date.compareTo(b.date); });
    return DailyReportPendingResult(List.unmodifiable(result), visitWarning: warning);
  }

  /// Reads every saved ID for the selected destination and immutable status category.
  /// Metadata pagination never treats a failed/unavailable route RPC as an endpoint.
  Future<DailyReportSiteHistoryResult> listSiteHistory(DailyReportMonthEntry anchor, {String? workerId}) async {
    final user = actor, category = anchor.saveState;
    final result = <DailyReportMonthEntry>[];
    final seen = <String>{};
    final uuid = RegExp(r'^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$');
    if ((workerId != null && !uuid.hasMatch(workerId)) ||
        (anchor.siteId == null && anchor.routeId == null)) { throw StateError('現場の対象を確認できません。'); }
    if (anchor.siteId != null || !anchor.isVisit) {
      DateTime? cursorDate; String? cursorId;
      for (;;) {
        checkActor(user);
        var query = client.from('daily_reports').select(
          'id,report_date,created_at,site_id,route_assignment_id,status,work_description,sites(name),route_assignments(route_name)${workerId == null ? '' : ',daily_report_workers!inner(worker_id)'}');
        if (anchor.siteId != null) { query = query.eq('site_id', anchor.siteId!); }
        else { query = query.eq('route_assignment_id', anchor.routeId!).isFilter('site_id', null); }
        if (workerId != null) query = query.eq('daily_report_workers.worker_id', workerId);
        String? supervisorFilter;
        switch (category) {
          case DailyReportSaveState.saved: query = query.inFilter('status', ['signed', 'completed']); break;
          case DailyReportSaveState.supervisorPending:
            query = query.eq('status', 'draft').not('representative_signature_json', 'is', null)
              .isFilter('supervisor_signature_json', null).isFilter('signature_json', null); break;
          case DailyReportSaveState.finalizationPending:
            query = query.eq('status', 'draft').not('representative_signature_json', 'is', null);
            supervisorFilter = 'supervisor_signature_json.not.is.null,signature_json.not.is.null'; break;
          case DailyReportSaveState.inputPending:
            query = query.eq('status', 'draft').isFilter('representative_signature_json', null); break;
        }
        final cursorFilter = cursorDate == null ? null : 'report_date.gt.${dateKey(cursorDate)},and(report_date.eq.${dateKey(cursorDate)},id.gt.$cursorId)';
        if (supervisorFilter != null && cursorFilter != null) { query = query.or('and(or($supervisorFilter),or($cursorFilter))'); }
        else if (supervisorFilter != null) { query = query.or(supervisorFilter); }
        else if (cursorFilter != null) { query = query.or(cursorFilter); }
        final rows = await query.order('report_date').order('id').range(0, 199);
        checkActor(user);
        for (final row in rows) {
          final id = row['id'], date = DateTime.tryParse(row['report_date']?.toString() ?? '');
          final site = row['site_id'] as String?, route = row['route_assignment_id'] as String?;
          final destination = site != null ? row['sites'] : row['route_assignments'];
          final name = destination is Map ? destination[site != null ? 'name' : 'route_name'] : null;
          if (id is! String || !uuid.hasMatch(id) || date == null || name is! String || name.isEmpty ||
              (anchor.siteId != null ? site != anchor.siteId : site != null || route != anchor.routeId) ||
              !seen.add('report:$id') || (cursorDate != null && (date.isBefore(cursorDate) ||
                (date == cursorDate && id.compareTo(cursorId!) <= 0)))) { throw StateError('日報の現場・順序を確認できません。'); }
          final entry = DailyReportMonthEntry(id: id, date: date, name: name, status: row['status']?.toString() ?? '',
            siteId: site, routeId: route,
            reporterSigned: category == DailyReportSaveState.supervisorPending || category == DailyReportSaveState.finalizationPending,
            supervisorSigned: category == DailyReportSaveState.finalizationPending,
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''));
          if (entry.saveState != category) throw StateError('日報の保存状態が変わりました。');
          result.add(entry);cursorDate = date;cursorId = id;
        }
        if (rows.length < 200) break;
      }
    }
    String? warning;
    if (anchor.siteId != null || anchor.isVisit) {
      try {
        final companies = await client.from('company_members').select('company_id').eq('user_id', user).order('company_id');
        checkActor(user);
        final companiesSeen = <String>{};
        for (final company in companies) {
          final cid = company['company_id'];
          if (cid is! String || !uuid.hasMatch(cid) || !companiesSeen.add(cid)) throw StateError('会社を確認できません。');
          DateTime? cursorDate; String? cursorId;
          for (;;) {
            final raw = await client.rpc('list_site_route_visit_reports', params: {
              'p_company_id': cid, 'p_site_id': anchor.siteId,
              'p_route_assignment_id': anchor.siteId == null ? anchor.routeId : null,
              'p_site_name': anchor.siteId == null ? anchor.name : null,
              'p_category': category.name, 'p_worker_id': workerId,
              'p_after_date': cursorDate == null ? null : dateKey(cursorDate), 'p_after_id': cursorId, 'p_limit': 200,
            });
            checkActor(user);
            if (raw is! Map || raw['actor_id'] != user || raw['company_id'] != cid || raw['category'] != category.name || raw['entries'] is! List) throw StateError('訪問日報の対象を確認できません。');
            final rows = raw['entries'] as List;
            if (rows.length > 200) throw StateError('訪問日報の件数を確認できません。');
            for (final row in rows) {
              if (row is! Map || row['company_id'] != cid) throw StateError('訪問日報の会社を確認できません。');
              String text(String key) { final v = row[key];if (v is! String || v.isEmpty) throw StateError('訪問日報の識別情報を確認できません。');return v; }
              final id = text('id'), date = DateTime.tryParse(text('report_date'));
              final site = row['site_id'] as String?;
              if (!uuid.hasMatch(id) || date == null || !seen.add('visit:$id') ||
                  (anchor.siteId != null ? site != anchor.siteId : site != null || row['route_assignment_id'] != anchor.routeId || row['site_name'] != anchor.name) ||
                  (cursorDate != null && (date.isBefore(cursorDate) || (date == cursorDate && id.compareTo(cursorId!) <= 0)))) { throw StateError('訪問日報の現場・順序を確認できません。'); }
              final context = RouteVisitReportContext(sourceClockInId: text('source_clock_in_id'), routeAssignmentId: text('route_assignment_id'),
                routeStopId: text('route_stop_id'), startCaptureId: text('start_capture_id'), endCaptureId: text('end_capture_id'));
              context.toRpcParams();
              final entry = DailyReportMonthEntry(id: id, date: date, name: text('site_name'), status: text('status'), siteId: site,
                routeId: context.routeAssignmentId, visitContext: context, reporterSigned: row['reporter_signed'] == true,
                supervisorSigned: row['supervisor_signed'] == true, createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''));
              if (entry.saveState != category || row['reporter_signed'] is! bool || row['supervisor_signed'] is! bool) throw StateError('訪問日報の保存状態を確認できません。');
              result.add(entry);cursorDate = date;cursorId = id;
            }
            if (rows.length < 200) break;
          }
        }
      } catch (_) {
        checkActor(user);
        result.removeWhere((entry) => entry.isVisit);
        warning = '訪問日報を含む全期間は未確認です。前後の日報の範囲を再取得してください。';
      }
    }
    checkActor(user);
    result.sort((a, b) { final date = a.date.compareTo(b.date);if (date != 0) return date;
      final created = (a.createdAt ?? a.date).compareTo(b.createdAt ?? b.date);
      return created != 0 ? created : a.id.compareTo(b.id); });
    return DailyReportSiteHistoryResult(List.unmodifiable(result), complete: warning == null, warning: warning);
  }

  /// Classifies actual saved reports using evidence metadata, without downloading photos.
  Future<bool> hasPhotos(DailyReportMonthEntry entry, {required String expectedActor}) async {
    checkActor(expectedActor);
    final records = entry.isVisit
        ? await reports.loadVisitEvidence(entry.visitContext!, date: entry.date)
        : await reports.loadAttendanceEvidence(reportId: entry.id, date: entry.date,
            siteId: entry.siteId, routeAssignmentId: entry.routeId);
    checkActor(expectedActor);
    return records.any((record) => record.storagePath.isNotEmpty);
  }

  static void requireCompletePhotos(List<DailyReportPdfEvidence> photos) {
    if (photos.any(
      (photo) =>
          photo.downloadFailed ||
          (photo.record.storagePath.isNotEmpty && photo.photoBytes == null),
    )) {
      throw StateError('保存済み写真を取得できない日報があります。再読み込みしてから保存してください。');
    }
  }

  Future<DailyReportMonthDocument> loadOne(
    DailyReportMonthEntry entry, {
    required String expectedActor,
  }) async {
    checkActor(expectedActor);
    final report = entry.visitContext != null
        ? await reports.loadVisitReport(entry.visitContext!)
        : await reports.loadReport(
            date: entry.date, siteId: entry.siteId,
            routeAssignmentId: entry.routeId, reportId: entry.id,
          );
    checkActor(expectedActor);
    if (report == null || report.id != entry.id) {
      throw StateError('日報が更新されています。一覧を再読み込みしてください。');
    }
    final records = entry.isVisit
        ? await reports.loadVisitEvidence(entry.visitContext!, date: report.date)
        : await reports.loadAttendanceEvidence(
      reportId: report.id,
      date: report.date,
      siteId: report.siteId,
      routeAssignmentId: report.routeAssignmentId,
    );
    checkActor(expectedActor);
    final photos = await reports.loadPdfEvidence(records);
    checkActor(expectedActor);
    requireCompletePhotos(photos);
    return DailyReportMonthDocument(report, photos);
  }
}


