import 'dart:convert';
import 'line_history_parser.dart';
import 'line_import_draft.dart';
import 'line_reading_rules.dart';
import 'line_reading_rule_application.dart';
import 'line_saved_monthly_merge.dart';

/// The supplied history ends in September 2026: 33 editable months.
List<DateTime> lineHistoricalMonths() => List.unmodifiable(
  List.generate(33, (index) => DateTime(2024, index + 1)));

List<Map<String, dynamic>> lineHistorySources(String text) {
  final parsed = const LineHistoryParser().parse(text.replaceFirst('\uFEFF', ''));
  final unique = <String, Map<String, dynamic>>{};
  final occurrences = <String, int>{};
  for (final message in parsed.messages) {
    final source = <String, dynamic>{
      'body': message.body, 'sent_at': message.timestamp.toUtc().toIso8601String(),
      'sender_display_name': message.sender, 'source_type': 'history',
    };
    final base = 'history:${lineSourceFingerprint(source)}';
    final occurrence = (occurrences[base] ?? 0) + 1;
    occurrences[base] = occurrence;
    final id = occurrence == 1 ? base : '$base:$occurrence';
    source['id'] = id;
    unique[id] = source;
  }
  return unique.values.toList(growable: false);
}

({List<Map<String, dynamic>> sources, List<Map<String, dynamic>> rows,
  List<String> unreadableSourceIds})
lineMonthlyCandidates(List<Map<String, dynamic>> history, DateTime month,
    {List<Map<String, dynamic>> previous = const [],
     List<Map<String, dynamic>> workers = const [],
     List<Map<String, dynamic>> sites = const [],
     List<LineReadingRule> readingRules = const []}) {
  final extracted = LineImportDraft.extract(
    lineCanonicalImportPosts(history, previous: previous), month, previous: previous, readingLabels: readingRules.where((r) =>
      r.kind != LineReadingKind.site && r.kind != LineReadingKind.worker).map((r) => r.phrase));
  var rows = [for (final row in extracted.rows) Map<String, dynamic>.from(row)];
  // Interpret every worker against the same original names before any aliases.
  final readingRows = [for (final row in rows) Map<String, dynamic>.from(row)];
  // A saved row may contain an older explicit correction without a marker.
  // Apply aliases only to newly extracted rows, never to retained fingerprints.
  final retained = {for (final row in previous)
    '${row['row_id']}:${row['source_fingerprint']}'};
  for (final row in rows) {
    if (!retained.contains('${row['row_id']}:${row['source_fingerprint']}') &&
        row['confirmed'] != true && row['manually_edited'] != true && row['edited'] != true) {
      lineApplyReadingFacts(row, history, readingRows, readingRules);
      for (final entry in [
        ('site_name', LineReadingKind.site, sites),
        ('worker_name', LineReadingKind.worker, workers),
      ]) {
        final aliases = readingRules.where((r) => r.kind == entry.$2 &&
          r.phrase == row[entry.$1]).toList();
        if (aliases.length != 1) continue;
        final targets = entry.$3.where((r) => r['name'] == aliases.single.value).toList();
        // Names are the existing dictionary contract: resolve only a unique ID.
        if (targets.length == 1 && targets.single['id'] != null) {
          row[entry.$1] = aliases.single.value;
        }
      }
    }
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
  // Recheck after resolving names to IDs: an old edited row has an ID,
  // while a newly imported copy initially has only the worker's name.
  final counts = <String, int>{};
  String workerDay(Map<String, dynamic> row) => lineWorkRecordIdentity(row);
  for (final row in rows.where((row) => row['excluded'] != true)) {
    final key = workerDay(row);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  for (final row in rows.where((row) => row['excluded'] != true)) {
    if ((counts[workerDay(row)] ?? 0) > 1) {
      row['confirmed'] = false;
      row['review_reason'] = '同日の同じ勤務が複数行あります。重複・訂正を確認してください。';
    }
  }
  rows = lineReconcileSavedMonthlyRows(rows, previous);
  final used = <dynamic>{for (final row in rows) row['source_message_id'],
    for (final row in rows) if (row['completion_source_message_id'] != null) row['completion_source_message_id']};
  final sources = history.where((source) {
    final at = DateTime.tryParse(source['sent_at']?.toString() ?? '')?.toLocal();
    return used.contains(source['id']) ||
      (at?.year == month.year && at?.month == month.month);
  }).toList(growable: false);
  return (sources: sources, rows: rows, unreadableSourceIds: extracted.unreadableSourceIds);
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

/// Keep the original 33 months and allow later months, including this October.
List<DateTime> lineHistoryImportMonths({DateTime? through}) {
  final end = through ?? DateTime.now();
  final count = (end.year - 2024) * 12 + end.month;
  return List.unmodifiable(List.generate(count < 33 ? 33 : count,
    (index) => DateTime(2024, index + 1)));
}

/// File supplements keep prior posts; explicit replacement keeps received posts.
List<Map<String, dynamic>> lineMergeImportSources(
    List<Map<String, dynamic>> existing, List<Map<String, dynamic>> incoming,
    {bool replaceHistory = false}) {
  final merged = <String, Map<String, dynamic>>{};
  for (final source in [
    ...existing.where((source) =>
      !replaceHistory || source['source_type'] == 'received'),
    ...incoming,
  ]) {
    final id = source['id']?.toString();
    if (id != null && id.isNotEmpty) merged[id] = source;
  }
  return merged.values.toList(growable: false);
}

/// Coalesce only an unambiguous one-to-one received/exported copy.
/// Multiple identical posts remain separate and require the existing review.
List<Map<String, dynamic>> lineCanonicalImportPosts(
    List<Map<String, dynamic>> sources,
    {List<Map<String, dynamic>> previous = const []}) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final source in sources) {
    final at = DateTime.tryParse(source['sent_at']?.toString() ?? '');
    final body = source['body'];
    final sender = source['sender_display_name'];
    if (at == null || body is! String || sender is! String ||
        sender.trim().isEmpty) {
      continue;
    }
    final key = jsonEncode([at.millisecondsSinceEpoch ~/ 60000,
      sender.trim(), body.replaceAll('\r\n', '\n').trim()]);
    groups.putIfAbsent(key, () => []).add(source);
  }
  final suppressed = <String>{};
  for (final group in groups.values) {
    final received = group.where((s) => s['source_type'] == 'received').toList();
    final history = group.where((s) => s['source_type'] == 'history').toList();
    if (received.length != 1 || history.length != 1) continue;
    final copies = [received.single, history.single];
    final saved = copies.where((source) => previous.any((row) =>
      row['source_message_id'] == source['id'] &&
      row['source_fingerprint'] == lineSourceFingerprint(source))).toList();
    if (saved.length > 1) continue;
    final keep = saved.isNotEmpty ? saved.first : received.single;
    for (final copy in copies) {
      if (copy['id'] != keep['id']) suppressed.add(copy['id'].toString());
    }
  }
  return sources.where((s) => !suppressed.contains(s['id'])).toList(growable: false);
}

/// Include every month supplied in the file, retaining the original empty months.
List<DateTime> lineHistoryMonthsForSources(List<Map<String, dynamic>> sources) {
  var first = DateTime(2024);
  var last = DateTime(DateTime.now().year, DateTime.now().month);
  for (final source in sources) {
    final at = DateTime.tryParse(source['sent_at']?.toString() ?? '')?.toLocal();
    if (at == null || at.year < 1900 || at.year > 2100) continue;
    final month = DateTime(at.year, at.month);
    if (month.isBefore(first)) first = month;
    if (month.isAfter(last)) last = month;
  }
  final count = (last.year - first.year) * 12 + last.month - first.month + 1;
  return List.unmodifiable(List.generate(count,
    (index) => DateTime(first.year, first.month + index)));
}
