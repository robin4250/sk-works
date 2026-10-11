import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/supabase_backend.dart';
import 'daily_report_pdf_evidence.dart';
import 'daily_report_repository.dart';

class DailyReportMonthEntry {
  const DailyReportMonthEntry({
    required this.id,
    required this.date,
    required this.name,
    required this.status,
    this.siteId,
    this.routeId,
  });
  final String id, name, status;
  final DateTime date;
  final String? siteId, routeId;
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

  Future<List<DailyReportMonthEntry>> list(DateTime month) async {
    final user = actor;
    final result = <DailyReportMonthEntry>[];
    // Explicit pagination avoids silently truncating a month's accessible reports.
    for (var offset = 0; ; offset += 500) {
      checkActor(user);
      final rows = await client
          .from('daily_reports')
          .select(
            'id,report_date,site_id,route_assignment_id,status,sites(name),route_assignments(route_name)',
          )
          .gte('report_date', dateKey(DateTime(month.year, month.month)))
          .lt('report_date', dateKey(DateTime(month.year, month.month + 1)))
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
          ),
        );
      }
      if (rows.length < 500) break;
    }
    return result;
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
    final report = await reports.loadReport(
      date: entry.date,
      siteId: entry.siteId,
      routeAssignmentId: entry.routeId,
    );
    checkActor(expectedActor);
    if (report == null || report.id != entry.id) {
      throw StateError('日報が更新されています。一覧を再読み込みしてください。');
    }
    final records = await reports.loadAttendanceEvidence(
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
