import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'line_attendance_candidate_parser.dart';
import 'line_attendance_status_parser.dart';
import 'line_history_parser.dart';

String lineSourceFingerprint(Map<String, dynamic> source) => sha256.convert(utf8.encode(jsonEncode([
  source['id'], source['body'], source['sent_at'], source['sender_display_name'],
]))).toString();

/// Distinct sites and shifts on one day are separate work records.
String lineWorkRecordIdentity(Map<String, dynamic> row) => jsonEncode([
  row['work_date'], row['worker_id'] ?? row['worker_name'],
  row['site_id'] ?? row['site_name'], row['work_category'],
  row['shift_id'], row['shift_start'], row['shift_end'],
  row['start_time'], row['end_time'],
]);

class LineImportDraft {
  const LineImportDraft(this.rows, this.unreadableSourceIds);
  final List<Map<String, dynamic>> rows;
  final List<String> unreadableSourceIds;

  /// Unchanged sources retain explicit corrections. Changed sources need review.
  static LineImportDraft extract(List<Map<String, dynamic>> sources, DateTime month,
      {List<Map<String, dynamic>> previous = const [],
       Iterable<String> readingLabels = const []}) {
    final result = <Map<String, dynamic>>[];
    final unreadable = <String>[];
    final previousById = {for (final row in previous) row['row_id']: row};
    final ordered = sources.asMap().entries.toList()..sort((a, b) {
      final at = DateTime.tryParse(a.value['sent_at']?.toString() ?? '');
      final bt = DateTime.tryParse(b.value['sent_at']?.toString() ?? '');
      final order = at == null || bt == null ? 0 : at.compareTo(bt);
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
    final completionBySource = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ordered.length; i++) {
      final source = ordered[i].value;
      final body = source['body'];
      if (body is! String || !_hasWorkDate(body)) continue;
      final sender = source['sender_display_name'];
      if (sender is! String || sender.trim().isEmpty) continue;
      final matches = <Map<String, dynamic>>[];
      for (var next = i + 1; next < ordered.length; next++) {
        final candidate = ordered[next].value;
        // A copied group's reporter is not the destination reporter, even if
        // their display names match. Keep completion evidence in its origin.
        if ((source['saved_source_origin_group_id'] ?? source['saved_source_group_id']) !=
            (candidate['saved_source_origin_group_id'] ?? candidate['saved_source_group_id'])) continue;
        if (candidate['sender_display_name'] != sender) continue;
        final report = candidate['body'];
        if (report is! String) continue;
        if (_hasWorkDate(report) || lineBodyForReading(report).trim().startsWith('訂正')) break;
        if (const LineAttendanceStatusParser().parse(report).isNotEmpty) matches.add(candidate);
      }
      // Multiple reports cannot be safely chosen without manual review.
      if (matches.length == 1) completionBySource[source['id'].toString()] = matches.single;
    }
    for (final source in sources) {
      final id = source['id']?.toString() ?? '';
      final timestamp = DateTime.tryParse(source['sent_at']?.toString() ?? '');
      if (id.isEmpty || timestamp == null || source['body'] is! String) {
        unreadable.add(id);
        continue;
      }
      final body = lineBodyForReading(source['body'] as String);
      // DateTime rolls impossible dates forward. Never silently import that rollover.
      var first = body.trim().split('\n').first;
      const fullDigits = '０１２３４５６７８９';
      for (var digit = 0; digit < fullDigits.length; digit++) {
        first = first.replaceAll(fullDigits[digit], '$digit');
      }
      final dateMatch = RegExp(r'^(?:(\d{4})[/.年])?(\d{1,2})[/.月](\d{1,2})日?(?:[（(][^）)]*[）)])?(?:[ 　]*夜勤)?$').firstMatch(first);
      if (dateMatch != null) {
        final year = int.parse(dateMatch.group(1) ?? '${timestamp.toLocal().year}');
        final m = int.parse(dateMatch.group(2)!);
        final day = int.parse(dateMatch.group(3)!);
        final date = DateTime(year, m, day);
        if (date.year != year || date.month != m || date.day != day) {
          unreadable.add(id);
          continue;
        }
      }
      final candidates = const LineAttendanceCandidateParser().parseMessages([
        LineHistoryMessage(timestamp: timestamp.toLocal(), sender: source['sender_display_name']?.toString() ?? 'LINE', body: body),
      ], trailingLabels: readingLabels);
      final ownStatuses = const LineAttendanceStatusParser().parse(body);
      final completion = ownStatuses.isEmpty ? completionBySource[id] : null;
      final completionFingerprint = completion == null ? null : lineSourceFingerprint(completion);
      final statuses = ownStatuses.isNotEmpty ? ownStatuses : completion == null
        ? const <LineAttendanceStatus>[] : const LineAttendanceStatusParser().parse(completion['body'] as String);
      if (candidates.isEmpty) {
        unreadable.add(id);
        continue;
      }
      final fingerprint = lineSourceFingerprint(source);
      for (var index = 0; index < candidates.length; index++) {
        final candidate = candidates[index];
        if (candidate.workDate.year != month.year || candidate.workDate.month != month.month) continue;
        final rowId = '$id:$index';
        final old = previousById[rowId];
        if (old != null && old['source_fingerprint'] == fingerprint && old['completion_source_fingerprint'] == completionFingerprint) {
          result.add(Map<String, dynamic>.from(old));
          continue;
        }
        final matching = statuses.where((status) => status.siteName == candidate.siteName).toList();
        final status = matching.length == 1 ? matching.single : null;
        final inferredDay = status != null && !status.isRegularTime &&
          (status.overtimeHours > 0 || status.earlyHours > 0);
        result.add({
          'row_id': rowId, 'source_message_id': id, 'source_fingerprint': fingerprint,
          'reading_origin': {'kind': 'automatic', 'source_fingerprint': fingerprint,
            'phrases': {'site_name': candidate.siteName, 'worker_name': candidate.workerName}},
          if (completion != null) 'completion_source_message_id': completion['id'],
          if (completion != null) 'completion_source_fingerprint': completionFingerprint,
          'work_date': '${candidate.workDate.year.toString().padLeft(4, '0')}-${candidate.workDate.month.toString().padLeft(2, '0')}-${candidate.workDate.day.toString().padLeft(2, '0')}',
          'worker_name': candidate.workerName, 'site_name': candidate.siteName,
          'worker_id': null, 'site_id': null, 'customer_id': null,
          'man_days': status?.isRegularTime == true || inferredDay ? 1.0 : null,
          'man_days_inferred': inferredDay,
          'overtime_hours': status?.overtimeHours ?? 0.0,
          'early_hours': status?.earlyHours ?? 0.0,
          'night_work': status?.isNightWork ?? false,
          'work_category': status?.isHolidayWork == true ? (status?.isNightWork == true ? 'holiday_night' : 'holiday') : status?.isNightWork == true ? 'night' : 'day',
          'allowance_names': <String>[...?status?.allowanceNames],
          'steel_allowance': status?.hasSteelAllowance ?? false,
          'confirmed': false,
          'review_reason': old != null ? '元の投稿が変わりました。修正内容を確認してください。' : inferredDay
            ? '残業・早出の報告から1人工を仮置きしています。半日・人数・数量を確認してください。'
            : '作業員・現場・数量を確認してください。',
        });
      }
    }
    for (final old in previous.where((row) => row['row_id']?.toString().startsWith('manual:') == true)) {
      final date = DateTime.tryParse(old['work_date']?.toString() ?? '');
      if (date == null || date.year != month.year || date.month != month.month) continue;
      final matches = sources.where((s) => s['id'] == old['source_message_id']).toList();
      if (matches.length != 1) continue;
      final fingerprint = lineSourceFingerprint(matches.single);
      result.add({...old, if (fingerprint != old['source_fingerprint']) ...{
        'source_fingerprint': fingerprint, 'confirmed': false,
        'review_reason': '元の投稿が変わりました。手入力した内容を確認してください。',
      }});
    }
    result.sort((a, b) => '${a['work_date']}:${a['worker_name']}:${a['row_id']}'.compareTo('${b['work_date']}:${b['worker_name']}:${b['row_id']}'));
    final keys = <String, int>{};
    for (final row in result.where((row) => row['excluded'] != true)) {
      final key = lineWorkRecordIdentity(row);
      keys[key] = (keys[key] ?? 0) + 1;
    }
    for (final row in result.where((row) => row['excluded'] != true)) {
      final key = lineWorkRecordIdentity(row);
      if (keys[key]! > 1) {
        row['confirmed'] = false;
        row['review_reason'] = '同日の同じ勤務が複数行あります。重複・訂正を確認してください。';
      }
    }
    return LineImportDraft(List.unmodifiable(result), List.unmodifiable(unreadable));
  }

  static bool _hasWorkDate(String body) {
    var first = lineBodyForReading(body).trim().split('\n').first;
    const full = '０１２３４５６７８９';
    for (var i = 0; i < full.length; i++) { first = first.replaceAll(full[i], '$i'); }
    return RegExp(r'^(?:(\d{4})[/.年])?(\d{1,2})[/.月](\d{1,2})日?(?:[（(][^）)]*[）)])?').hasMatch(first);
  }

  static List<Map<String, dynamic>> aggregate(List<Map<String, dynamic>> rows, {required bool bySite}) {
    final totals = <String, Map<String, dynamic>>{};
    for (final row in rows.where((row) => row['confirmed'] == true && row['excluded'] != true &&
        (row['assumed_fields'] is! Map || (row['assumed_fields'] as Map).isEmpty))) {
      final key = row[bySite ? 'site_id' : 'worker_id']?.toString();
      if (key == null || key.isEmpty) continue;
      final total = totals.putIfAbsent(key, () => {'id': key, 'name': row[bySite ? 'site_name' : 'worker_name'],
        'man_days': 0.0, 'overtime_hours': 0.0, 'early_hours': 0.0, 'rows': 0});
      for (final field in ['man_days', 'overtime_hours', 'early_hours']) {
        total[field] = (total[field] as num).toDouble() + (row[field] as num? ?? 0).toDouble();
      }
      total['rows'] = (total['rows'] as int) + 1;
    }
    return List.unmodifiable(totals.values);
  }
}
