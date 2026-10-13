import 'daily_report_pdf_evidence.dart';

/// Only photo-mode records belong on the photograph pages. Failed captures
/// remain visible; manual time-only entries stay in the attendance view.
List<DailyReportPdfEvidence> dailyReportPhotoRecords(
  List<DailyReportPdfEvidence> evidence,
) =>
    [
      ...evidence.where(
        (item) => !item.record.timeOnly && !item.record.isTimeOnly,
      ),
    ]..sort((a, b) {
      final time = a.record.confirmedAt.compareTo(b.record.confirmedAt);
      if (time != 0) return time;
      final worker = a.record.workerName.compareTo(b.record.workerName);
      return worker != 0 ? worker : a.record.id.compareTo(b.record.id);
    });

String dailyReportPhotoLocation(DailyReportPdfEvidence item) {
  final address = item.record.capturedAddress?.trim() ?? '';
  if (address.isNotEmpty) return address;
  return item.record.stopLabel?.trim() ?? '';
}

String dailyReportPhotoTime(DailyReportPdfEvidence item) {
  final at = item.record.confirmedAt;
  return '${at.year}/${at.month.toString().padLeft(2, '0')}/${at.day.toString().padLeft(2, '0')} '
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}
