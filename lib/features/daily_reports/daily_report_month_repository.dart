import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'daily_report_pdf_evidence.dart';
import 'daily_report_repository.dart';
import 'route_visit_report_context.dart';

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
  });
  final String id, name, status;
  final DateTime date;
  final String? siteId, routeId;
  final RouteVisitReportContext? visitContext;
  final DateTime? createdAt;
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

