import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'line_attendance_candidate_parser.dart';
import 'line_attendance_status_parser.dart';
import 'line_history_parser.dart';

String lineSourceFingerprint(Map<String, dynamic> source) => sha256.convert(utf8.encode(jsonEncode([
  source['id'], source['body'], source['sent_at'], source['sender_display_name'],
]))).toString();

class LineImportDraft {
  const LineImportDraft(this.rows, this.unreadableSourceIds);
  final List<Map<String, dynamic>> rows;
  final List<String> unreadableSourceIds;

  /// Unchanged sources retain explicit corrections. Changed sources need review.
  static LineImportDraft extract(List<Map<String, dynamic>> sources, DateTime month,
      {List<Map<String, dynamic>> previous = const []}) {
    final result = <Map<String, dynamic>>[];
    final unreadable = <String>[];
    final previousById = {for (final row in previous) row['row_id']: row};
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
      final dateMatch = RegExp(r'^(?:(\d{4})[/.年])?(\d{1,2})[/.月](\d{1,2})日?(?:[（(][^）)]*[）)])?$').firstMatch(first);
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
      ]);
      final statuses = const LineAttendanceStatusParser().parse(body);
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
        if (old != null && old['source_fingerprint'] == fingerprint) {
          result.add(Map<String, dynamic>.from(old));
          continue;
        }
        final matching = statuses.where((status) => status.siteName == candidate.siteName).toList();
        final status = matching.length == 1 ? matching.single : null;
        result.add({
          'row_id': rowId, 'source_message_id': id, 'source_fingerprint': fingerprint,
          'work_date': '${candidate.workDate.year.toString().padLeft(4, '0')}-${candidate.workDate.month.toString().padLeft(2, '0')}-${candidate.workDate.day.toString().padLeft(2, '0')}',
          'worker_name': candidate.workerName, 'site_name': candidate.siteName,
          'worker_id': null, 'site_id': null, 'customer_id': null,
          'man_days': status?.isRegularTime == true ? 1.0 : null,
          'overtime_hours': status?.overtimeHours ?? 0.0,
          'early_hours': status?.earlyHours ?? 0.0,
          'night_work': status?.isNightWork ?? false,
          'work_category': status?.isHolidayWork == true ? (status?.isNightWork == true ? 'holiday_night' : 'holiday') : status?.isNightWork == true ? 'night' : 'day',
          'allowance_names': <String>[],
          'steel_allowance': status?.hasSteelAllowance ?? false,
          'confirmed': false,
          'review_reason': old != null ? '元の投稿が変わりました。修正内容を確認してください。' : '作業員・現場・数量を確認してください。',
        });
      }
    }
    result.sort((a, b) => '${a['work_date']}:${a['worker_name']}:${a['row_id']}'.compareTo('${b['work_date']}:${b['worker_name']}:${b['row_id']}'));
    final keys = <String, int>{};
    for (final row in result) {
      final key = '${row['work_date']}:${row['worker_id'] ?? row['worker_name']}';
      keys[key] = (keys[key] ?? 0) + 1;
    }
    for (final row in result) {
      final key = '${row['work_date']}:${row['worker_id'] ?? row['worker_name']}';
      if (keys[key]! > 1) {
        row['confirmed'] = false;
        row['review_reason'] = '同日の作業員が複数行あります。重複・複数現場を確認してください。';
      }
    }
    return LineImportDraft(List.unmodifiable(result), List.unmodifiable(unreadable));
  }

  static List<Map<String, dynamic>> aggregate(List<Map<String, dynamic>> rows, {required bool bySite}) {
    final totals = <String, Map<String, dynamic>>{};
    for (final row in rows.where((row) => row['confirmed'] == true && row['excluded'] != true)) {
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
