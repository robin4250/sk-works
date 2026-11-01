import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'line_import_draft.dart';

/// Review evidence only: a conflicting copy never replaces the destination row.
class LineSavedMonthlyMergeConflict {
  const LineSavedMonthlyMergeConflict(this.description, {this.blocking = false,
    this.beforeBody, this.afterBody});
  final String description;
  final bool blocking;
  /// Authorized preview only; never used to overwrite the retained original.
  final String? beforeBody, afterBody;
}

class LineSavedMonthlyMergePreview {
  const LineSavedMonthlyMergePreview({required this.sources, required this.rows,
    required this.addedCount, required this.duplicateCount,
    required this.outOfMonthCount, required this.conflicts});
  final List<Map<String, dynamic>> sources, rows;
  final int addedCount, duplicateCount, outOfMonthCount;
  final List<LineSavedMonthlyMergeConflict> conflicts;
  int get conflictCount => conflicts.length;
  bool get canSave => !conflicts.any((c) => c.blocking);
  int get excludedCount => rows.where((r) => r['excluded'] == true).length;
  int get reviewCount => rows.where((r) => r['excluded'] != true &&
    r['confirmed'] != true).length + conflictCount;
  List<String> get workDates => (rows.where((r) => r['excluded'] != true)
    .map((r) => r['work_date'].toString()).toSet().toList()..sort());
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
  Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

String _identity(Map<String, dynamic> row) => jsonEncode([
  row['work_date'], row['site_id'] ?? row['site_name'],
  row['worker_id'] ?? row['worker_name'], row['work_category'],
  // Explicit shifts can distinguish two jobs at one site on the same day.
  row['shift_id'], row['shift_start'], row['shift_end'],
  row['start_time'], row['end_time'],
]);

bool _sameOrUnresolvedIdentity(Map<String, dynamic> a, Map<String, dynamic> b) {
  bool entity(String id, String name) {
    final ai = a[id]?.toString().trim() ?? '';
    final bi = b[id]?.toString().trim() ?? '';
    if (ai.isNotEmpty && bi.isNotEmpty) return ai == bi;
    final an = a[name]?.toString().trim() ?? '';
    final bn = b[name]?.toString().trim() ?? '';
    return an.isNotEmpty && an == bn;
  }
  return entity('worker_id', 'worker_name') && entity('site_id', 'site_name') &&
    ['work_date', 'work_category', 'shift_id', 'shift_start', 'shift_end',
      'start_time', 'end_time'].every((key) => a[key] == b[key]);
}

bool _resolvedIdentity(Map<String, dynamic> row) =>
  ['worker_id', 'site_id'].every((key) =>
    row[key] is String && (row[key] as String).trim().isNotEmpty);

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canonical(value[k])};
  }
  if (value is List) return value.map(_canonical).toList();
  if (value is num) return value.toDouble();
  return value;
}

String _content(Map<String, dynamic> row) {
  final allowances = row['allowance_names'];
  final sorted = allowances is List
    ? (allowances.map((x) => x.toString()).toList()..sort()) : allowances;
  return jsonEncode(_canonical({
    for (final key in ['man_days', 'overtime_hours', 'early_hours',
      'night_work', 'steel_allowance', 'man_days_inferred', 'assumed_fields'])
      key: row[key],
    'allowance_names': sorted,
  }));
}

bool _inMonth(Object? raw, DateTime month) {
  if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return false;
  final date = DateTime.tryParse(raw);
  return date != null && date.year == month.year && date.month == month.month &&
    date.day == int.parse(raw.substring(8));
}

/// Reconciles a later LINE refresh with previously appended saved evidence.
/// Only a pair involving saved-copy provenance participates. Existing rows and
/// their decisions take priority; fresh received duplicates remain as evidence.
List<Map<String, dynamic>> lineReconcileSavedMonthlyRows(
    List<Map<String, dynamic>> rows, List<Map<String, dynamic>> previous) {
  final old = {for (final row in previous) row['row_id'].toString(): row};
  final result = rows.map(_copy).toList();
  final savedRelatedIds = <String>{};
  for (final row in previous.where((r) => r['saved_source_group_id'] is String)) {
    if (row['merge_duplicate_of'] != null) {
      savedRelatedIds.add(row['merge_duplicate_of'].toString());
    }
    if (row['merge_conflict_with'] is List) {
      savedRelatedIds.addAll((row['merge_conflict_with'] as List).map((id) => id.toString()));
    }
  }
  bool unchanged(Map<String, dynamic> row, Map<String, dynamic> saved) =>
    row['source_message_id'] == saved['source_message_id'] &&
    row['source_fingerprint'] == saved['source_fingerprint'] &&
    row['completion_source_fingerprint'] == saved['completion_source_fingerprint'];
  bool fromSaved(Map<String, dynamic> row) =>
    (row['saved_source_group_id'] is String &&
      (row['saved_source_group_id'] as String).isNotEmpty) ||
    savedRelatedIds.contains(row['row_id'].toString());
  final participating = <String>{};
  for (var i = 0; i < result.length; i++) {
    for (var j = i + 1; j < result.length; j++) {
      final a = result[i], b = result[j];
      if (a['excluded'] == true || b['excluded'] == true ||
          !(fromSaved(a) || fromSaved(b)) || !_sameOrUnresolvedIdentity(a, b)) continue;
      participating.add(a['row_id'].toString());
      participating.add(b['row_id'].toString());
    }
  }
  // Earlier parser duplicate warnings must not erase a saved explicit decision.
  for (var i = 0; i < result.length; i++) {
    final row = result[i], saved = old[result[i]['row_id'].toString()];
    if (saved != null && participating.contains(row['row_id'].toString()) &&
        unchanged(row, saved)) result[i] = _copy(saved);
  }
  final order = List<int>.generate(result.length, (i) => i)..sort((a, b) {
    final ao = old.containsKey(result[a]['row_id'].toString());
    final bo = old.containsKey(result[b]['row_id'].toString());
    return ao == bo ? a.compareTo(b) : ao ? -1 : 1;
  });
  final active = <Map<String, dynamic>>[];
  for (final index in order) {
    final row = result[index];
    if (row['excluded'] == true) continue;
    final matches = active.where((other) => (fromSaved(row) || fromSaved(other)) &&
      _sameOrUnresolvedIdentity(other, row)).toList();
    // Never rewrite a previously saved row as a side effect of receiving a post.
    if (matches.isEmpty || old.containsKey(row['row_id'].toString())) {
      active.add(row);
      continue;
    }
    row['excluded'] = true;
    row['confirmed'] = false;
    if (matches.length == 1 && _resolvedIdentity(matches.single) &&
        _resolvedIdentity(row) && _content(matches.single) == _content(row)) {
      row['merge_duplicate_of'] = matches.single['row_id'];
      row['review_reason'] = '追加済みの保存データと一致したため二重計上しません。';
    } else {
      row['merge_conflict_with'] = matches.map((other) => other['row_id']).toList();
      row['review_reason'] = '追加済みの保存データと相違があります。受信分は計算対象外として原文確認を待ちます。';
    }
  }
  return result;
}

/// Appends saved evidence without editing either source workspace or originals.
/// The caller saves this preview through the existing destination CAS command.
LineSavedMonthlyMergePreview linePreviewSavedMonthlyMerge({
  required DateTime month, required String sourceGroupId,
  required List<Map<String, dynamic>> targetSources,
  required List<Map<String, dynamic>> targetRows,
  required List<Map<String, dynamic>> incomingSources,
  required List<Map<String, dynamic>> incomingRows,
}) {
  final conflicts = <LineSavedMonthlyMergeConflict>[];
  final sources = <String, Map<String, dynamic>>{};
  final rows = targetRows.map(_copy).toList();
  final byRowId = <String, Map<String, dynamic>>{
    for (final row in rows) row['row_id'].toString(): row,
  };
  if (sourceGroupId.trim().isEmpty || byRowId.length != rows.length) {
    conflicts.add(const LineSavedMonthlyMergeConflict(
      'グループまたは保存済み行の識別を確認できません。', blocking: true));
  }
  for (final source in targetSources) {
    final id = source['id']?.toString() ?? '';
    if (id.isEmpty || (sources.containsKey(id) &&
        lineSourceFingerprint(sources[id]!) != lineSourceFingerprint(source))) {
      conflicts.add(const LineSavedMonthlyMergeConflict(
        'まとめ先の原文IDが重複しています。', blocking: true));
      continue;
    }
    sources[id] = _copy(source);
  }
  final mapped = <String, Map<String, dynamic>>{};
  final blockedIds = <String>{};
  for (final original in incomingSources) {
    final oldId = original['id']?.toString() ?? '';
    if (oldId.isEmpty) {
      conflicts.add(const LineSavedMonthlyMergeConflict(
        '追加元の原文IDを確認できません。', blocking: true));
      continue;
    }
    final copy = _copy(original);
    final newId = 'saved:$sourceGroupId:$oldId';
    copy.addAll({'id': newId, 'source_type': 'history',
      'saved_source_group_id': sourceGroupId, 'saved_source_message_id': oldId,
      'saved_source_origin_group_id': original['saved_source_origin_group_id'] ??
        original['saved_source_group_id'] ?? sourceGroupId});
    final existing = sources[newId] ?? mapped[oldId];
    if (existing != null && lineSourceFingerprint(existing) != lineSourceFingerprint(copy)) {
      blockedIds.add(oldId);
      conflicts.add(LineSavedMonthlyMergeConflict(
        '追加済み原文が変更されています（$oldId）。元の保存内容は保持します。', blocking: true,
        beforeBody: existing['body'] is String ? existing['body'] as String : null,
        afterBody: copy['body'] is String ? copy['body'] as String : null));
      continue;
    }
    mapped[oldId] = copy;
    sources.putIfAbsent(newId, () => copy);
  }
  var added = 0, duplicates = 0, outside = 0;
  for (final original in incomingRows) {
    if (!_inMonth(original['work_date'], month)) { outside++; continue; }
    final oldSourceId = original['source_message_id']?.toString() ?? '';
    final source = mapped[oldSourceId];
    if (source == null || blockedIds.contains(oldSourceId)) {
      conflicts.add(const LineSavedMonthlyMergeConflict(
        '対象行の原文が不足または変更されています。', blocking: true));
      continue;
    }
    final row = _copy(original);
    final oldRowId = original['row_id']?.toString() ?? '';
    if (oldRowId.isEmpty) {
      conflicts.add(const LineSavedMonthlyMergeConflict(
        '追加元の行IDを確認できません。', blocking: true));
      continue;
    }
    final rowId = oldRowId.startsWith('$oldSourceId:')
      ? '${source['id']}${oldRowId.substring(oldSourceId.length)}'
      : 'manual:saved:${sha256.convert(utf8.encode(jsonEncode([sourceGroupId, oldRowId])))}';
    row.addAll({'row_id': rowId, 'source_message_id': source['id'],
      'source_fingerprint': lineSourceFingerprint(source),
      'saved_source_group_id': sourceGroupId, 'saved_source_row_id': oldRowId});
    if (row['reading_origin'] is Map) {
      row['reading_origin'] = {...Map<String, dynamic>.from(row['reading_origin'] as Map),
        'source_fingerprint': row['source_fingerprint']};
    }
    final completionId = original['completion_source_message_id']?.toString();
    if (completionId != null) {
      final completion = mapped[completionId];
      if (completion == null || blockedIds.contains(completionId)) {
        conflicts.add(const LineSavedMonthlyMergeConflict(
          '勤務終了報告の原文を確認できません。', blocking: true));
        continue;
      }
      row['completion_source_message_id'] = completion['id'];
      row['completion_source_fingerprint'] = lineSourceFingerprint(completion);
    }
    final retained = byRowId[rowId];
    if (retained != null) {
      // Re-import cannot erase destination edits, excluded flags or confirmation.
      duplicates++;
      if (_identity(retained) != _identity(row) || _content(retained) != _content(row)) {
        conflicts.add(LineSavedMonthlyMergeConflict(
          '${row['work_date']} ${row['worker_name']}：追加済み行と相違があります。まとめ先の手直しを保持します。'));
        final conflictId = 'manual:saved-conflict:${sha256.convert(utf8.encode(
          jsonEncode([rowId, _identity(row), _content(row)])))}';
        if (!byRowId.containsKey(conflictId)) {
          final evidence = {...row, 'row_id': conflictId, 'excluded': true,
            'confirmed': false, 'merge_conflict_with': [retained['row_id']],
            'review_reason': '追加元の保存済み行と相違があります。まとめ先の手直しを保持し、この比較行は計算対象外です。'};
          rows.add(evidence);
          byRowId[conflictId] = evidence;
        }
      }
      continue;
    }
    final matches = rows.where((r) => r['excluded'] != true &&
      _sameOrUnresolvedIdentity(r, row)).toList();
    if (matches.isNotEmpty) {
      row['excluded'] = true;
      row['confirmed'] = false;
      if (matches.length == 1 && _resolvedIdentity(matches.single) &&
          _resolvedIdentity(row) && _content(matches.single) == _content(row)) {
        duplicates++;
        row['merge_duplicate_of'] = matches.single['row_id'];
        row['review_reason'] = '同じ勤務の保存済み記録と一致したため二重計上しません。';
      } else {
        row['merge_conflict_with'] = matches.map((r) => r['row_id']).toList();
        row['review_reason'] = '同じ勤務の内容に相違があります。追加分は計算対象外です。原文を確認してください。';
        conflicts.add(LineSavedMonthlyMergeConflict(
          '${row['work_date']} ${row['site_name']} ${row['worker_name']}：数量・手当等に相違があります。'));
      }
    } else { added++; }
    rows.add(row);
    byRowId[rowId] = row;
  }
  if (sources.length > 10000 || rows.length > 10000) {
    conflicts.add(const LineSavedMonthlyMergeConflict(
      '一度に保存できる件数を超えています。対象を分けてください。', blocking: true));
  }
  return LineSavedMonthlyMergePreview(sources: List.unmodifiable(sources.values),
    rows: List.unmodifiable(rows), addedCount: added, duplicateCount: duplicates,
    outOfMonthCount: outside, conflicts: List.unmodifiable(conflicts));
}
