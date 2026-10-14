import 'line_history_parser.dart';
import 'line_import_draft.dart';

/// The supplied history ends in September 2026: 33 editable months.
List<DateTime> lineHistoricalMonths() => List.unmodifiable(
  List.generate(33, (index) => DateTime(2024, index + 1)));

List<Map<String, dynamic>> lineHistorySources(String text) {
  final parsed = const LineHistoryParser().parse(text.replaceFirst('\uFEFF', ''));
  final unique = <String, Map<String, dynamic>>{};
  for (final message in parsed.messages) {
    final source = <String, dynamic>{
      'body': message.body, 'sent_at': message.timestamp.toUtc().toIso8601String(),
      'sender_display_name': message.sender, 'source_type': 'history',
    };
    final id = 'history:' + lineSourceFingerprint(source);
    source['id'] = id;
    unique[id] = source;
  }
  return unique.values.toList(growable: false);
}

({List<Map<String, dynamic>> sources, List<Map<String, dynamic>> rows})
lineMonthlyCandidates(List<Map<String, dynamic>> history, DateTime month,
    {List<Map<String, dynamic>> previous = const [],
     List<Map<String, dynamic>> workers = const [],
     List<Map<String, dynamic>> sites = const []}) {
  final extracted = LineImportDraft.extract(history, month, previous: previous);
  final rows = [for (final row in extracted.rows) Map<String, dynamic>.from(row)];
  for (final row in rows) {
    if (row['worker_id'] == null) {
      final matches = workers.where((w) => w['name'] == row['worker_name']).toList();
      if (matches.length == 1) row['worker_id'] = matches.single['id'];
    }
    if (row['site_id'] == null) {
      final matches = sites.where((s) => s['name'] == row['site_name']).toList();
      if (matches.length == 1) {
        row['site_id'] = matches.single['id'];
        row['customer_id'] = matches.single['customer_id'];
      }
    }
  }
  final used = rows.map((r) => r['source_message_id']).toSet();
  final sources = history.where((source) {
    final at = DateTime.tryParse(source['sent_at']?.toString() ?? '')?.toLocal();
    return used.contains(source['id']) ||
      (at?.year == month.year && at?.month == month.month);
  }).toList(growable: false);
  return (sources: sources, rows: rows);
}

/// Reuse only a name explicitly saved with this historical quote.
String? lineHistoricalFormalSiteName(Map<String, dynamic> snapshot, String siteId) {
  final lines = snapshot['lines'];
  if (lines is! List) return null;
  final names = <String>{};
  for (final line in lines.whereType<Map>()) {
    if (line['site_id'] != siteId || line['rates'] is! Map) continue;
    final name = (line['rates'] as Map)['site_name']?.toString().trim();
    if (name != null && name.isNotEmpty) names.add(name);
  }
  return names.length == 1 ? names.single : null;
}
