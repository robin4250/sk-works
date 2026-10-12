import 'daily_report_month_repository.dart';

String dailyReportDestinationKey(DailyReportMonthEntry entry) {
  if (entry.siteId != null) return 'site:${entry.siteId}';
  if (entry.isVisit) return 'visit:${entry.routeId}:${entry.name}';
  return 'route:${entry.routeId}';
}

/// Date then actual creation time; kinds never move a newer record ahead of an older one.
List<DailyReportMonthEntry> chronologicalDailyReports(Iterable<DailyReportMonthEntry> entries) =>
    entries.toList()..sort((a, b) {
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      final created = (a.createdAt ?? a.date).compareTo(b.createdAt ?? b.date);
      return created != 0 ? created : a.id.compareTo(b.id);
    });

int? nextDailyReportDay(List<DailyReportMonthEntry> entries, int index) {
  if (index < 0 || index >= entries.length) return null;
  final current = DailyReportMonthRepository.dateKey(entries[index].date);
  for (var i = index + 1; i < entries.length; i++) {
    if (DailyReportMonthRepository.dateKey(entries[i].date) != current) return i;
  }
  return null;
}
