import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_saved_monthly_merge.dart';

Map<String, dynamic> source(String id, int day, {String? posted, String? body}) => {
  'id': id, 'body': body ?? '10月${day}日\n現場A 山田\n現場A 定時',
  'sent_at': posted ?? '2026-10-${day.toString().padLeft(2, '0')}T08:00:00Z',
  'sender_display_name': '投稿者', 'source_type': 'received',
};

Map<String, dynamic> row(Map<String, dynamic> s, int day, {
  String site = 'site-a', String category = 'day', num days = 1,
  bool confirmed = true, bool excluded = false,
}) => {
  'row_id': '${s['id']}:0', 'source_message_id': s['id'],
  'source_fingerprint': lineSourceFingerprint(s),
  'work_date': '2026-10-${day.toString().padLeft(2, '0')}',
  'site_id': site, 'site_name': '現場A', 'worker_id': 'worker-a',
  'worker_name': '山田', 'work_category': category,
  'man_days': days, 'overtime_hours': 0.0, 'early_hours': 0.0,
  'night_work': false, 'steel_allowance': false, 'man_days_inferred': false,
  'allowance_names': <String>[], 'confirmed': confirmed, 'excluded': excluded,
};

LineSavedMonthlyMergePreview merge({
  List<Map<String, dynamic>> targetSources = const [],
  List<Map<String, dynamic>> targetRows = const [],
  required List<Map<String, dynamic>> incomingSources,
  required List<Map<String, dynamic>> incomingRows,
}) => linePreviewSavedMonthlyMerge(month: DateTime(2026, 10),
  sourceGroupId: 'old-group', targetSources: targetSources,
  targetRows: targetRows, incomingSources: incomingSources, incomingRows: incomingRows);

void main() {
  test('October 1-7 append to 8-20 and later 30 stays in the same month', () {
    final existing = [for (var d = 8; d <= 20; d++) source('live$d', d)];
    final old = [for (var d = 1; d <= 7; d++) source('past$d', d)];
    final before = jsonEncode(old);
    final preview = merge(targetSources: existing,
      targetRows: [for (var d = 8; d <= 20; d++) row(existing[d - 8], d)],
      incomingSources: old, incomingRows: [for (var d = 1; d <= 7; d++) row(old[d - 1], d)]);
    expect(preview.addedCount, 7);
    expect(preview.workDates, hasLength(20));
    expect(preview.canSave, true);
    expect(jsonEncode(old), before);
    final later = source('live30', 30);
    final updated = merge(targetSources: [...preview.sources, later],
      targetRows: [...preview.rows, row(later, 30)],
      incomingSources: old, incomingRows: [for (var d = 1; d <= 7; d++) row(old[d - 1], d)]);
    expect(updated.addedCount, 0);
    expect(updated.duplicateCount, 7);
    expect(updated.rows, hasLength(21));
    expect(updated.workDates.last, '2026-10-30');
  });

  test('arrival in November still uses the October work date', () {
    final s = source('late', 30, posted: '2026-11-01T08:00:00Z');
    final extracted = lineMonthlyCandidates([s], DateTime(2026, 10));
    expect(extracted.rows.single['work_date'], '2026-10-30');
    final result = merge(incomingSources: [s], incomingRows: extracted.rows);
    expect(result.workDates, ['2026-10-30']);
    expect(result.sources.single['sent_at'], s['sent_at']);
  });

  test('different body month is excluded even when posted in target month', () {
    final s = source('other', 1);
    final r = {...row(s, 1), 'work_date': '2026-09-30'};
    final result = merge(incomingSources: [s], incomingRows: [r]);
    expect(result.rows, isEmpty);
    expect(result.outOfMonthCount, 1);
  });

  test('copy namespaces source and automatic row and recomputes fingerprints', () {
    final s = source('one', 1);
    final r = row(s, 1);
    final result = merge(incomingSources: [s], incomingRows: [r]);
    final copied = result.sources.single;
    expect(copied['id'], 'saved:old-group:one');
    expect(copied['source_type'], 'history');
    expect(copied['body'], s['body']);
    expect(copied['saved_source_message_id'], 'one');
    expect(result.rows.single['row_id'], 'saved:old-group:one:0');
    expect(result.rows.single['source_fingerprint'], lineSourceFingerprint(copied));
    expect(result.rows.single['source_fingerprint'], isNot(r['source_fingerprint']));
    expect(s['id'], 'one');
  });

  test('same attendance is saved as excluded evidence and destination stays exact', () {
    final a = source('target', 1), b = source('copy', 1);
    final retained = {...row(a, 1), 'review_reason': '本人確認済み'};
    final result = merge(targetSources: [a], targetRows: [retained],
      incomingSources: [b], incomingRows: [row(b, 1)]);
    expect(result.duplicateCount, 1);
    expect(result.addedCount, 0);
    expect(result.rows.first, retained);
    expect(result.rows.last['excluded'], true);
    expect(result.rows.last['merge_duplicate_of'], retained['row_id']);
    expect(result.workDates, ['2026-10-01']);
  });

  test('changed quantity never overwrites or double counts an existing attendance', () {
    final a = source('target', 1), b = source('correction', 1);
    final retained = row(a, 1, days: .5);
    final result = merge(targetSources: [a], targetRows: [retained],
      incomingSources: [b], incomingRows: [row(b, 1)]);
    expect(result.conflictCount, 1);
    expect(result.rows.first, retained);
    expect(result.rows.last['excluded'], true);
    expect(result.rows.last['merge_conflict_with'], [retained['row_id']]);
    expect(result.canSave, true); // Evidence can be saved for explicit review.
    expect(result.rows.where((r) => r['excluded'] != true)
      .fold<num>(0, (sum, r) => sum + (r['man_days'] as num)), .5);
  });

  test('same day at different sites and shifts are separate attendances', () {
    final a = source('target', 1), b = source('other', 1), c = source('night', 1);
    final result = merge(targetSources: [a], targetRows: [row(a, 1)],
      incomingSources: [b, c], incomingRows: [
        row(b, 1, site: 'site-b'), row(c, 1, category: 'night'),
      ]);
    expect(result.addedCount, 2);
    expect(result.rows.where((r) => r['excluded'] != true), hasLength(3));
    expect(result.conflictCount, 0);
  });

  test('explicit separate shift identifiers never collapse', () {
    final a = source('a', 1), b = source('b', 1);
    final result = merge(targetSources: [a], targetRows: [{...row(a, 1), 'shift_id': 'morning'}],
      incomingSources: [b], incomingRows: [{...row(b, 1), 'shift_id': 'evening'}]);
    expect(result.addedCount, 1);
    expect(result.duplicateCount, 0);
  });

  test('reimport retains destination manual edits and confirmation exactly', () {
    final s = source('old', 1);
    final first = merge(incomingSources: [s], incomingRows: [row(s, 1)]);
    final edited = {...first.rows.single, 'man_days': .5, 'confirmed': true,
      'manually_edited': true, 'review_reason': '修正確認済み'};
    final again = merge(targetSources: first.sources, targetRows: [edited],
      incomingSources: [s], incomingRows: [row(s, 1)]);
    expect(again.rows.first, edited);
    expect(again.rows.last['excluded'], true);
    expect(again.rows.last['merge_conflict_with'], [edited['row_id']]);
    expect(again.conflictCount, 1);
    expect(again.addedCount, 0);
    final repeated = merge(targetSources: again.sources, targetRows: again.rows,
      incomingSources: [s], incomingRows: [row(s, 1)]);
    expect(repeated.rows, again.rows);
  });

  test('changed original under the same copied ID blocks saving and keeps old bytes', () {
    final s = source('one', 1);
    final first = merge(incomingSources: [s], incomingRows: [row(s, 1)]);
    final changed = {...s, 'body': '訂正された別の本文'};
    final again = merge(targetSources: first.sources, targetRows: first.rows,
      incomingSources: [changed], incomingRows: [row(changed, 1)]);
    expect(again.canSave, false);
    expect(again.sources.single, first.sources.single);
    expect(again.rows, first.rows);
    expect(again.conflicts.first.beforeBody, s['body']);
    expect(again.conflicts.first.afterBody, changed['body']);
  });

  test('manual row and completion evidence mappings are stable', () {
    final s = source('start', 1), end = source('end', 1, body: '現場A 定時');
    final original = {...row(s, 1), 'row_id': 'manual:one',
      'completion_source_message_id': end['id'],
      'completion_source_fingerprint': lineSourceFingerprint(end)};
    final first = merge(incomingSources: [s, end], incomingRows: [original]);
    expect(first.rows.single['row_id'].toString(), startsWith('manual:saved:'));
    expect(first.rows.single['completion_source_message_id'], 'saved:old-group:end');
    expect(first.rows.single['completion_source_fingerprint'],
      lineSourceFingerprint(first.sources.last));
    final again = merge(targetSources: first.sources, targetRows: first.rows,
      incomingSources: [s, end], incomingRows: [original]);
    expect(again.rows, first.rows);
  });

  test('missing source or completion evidence prevents saving', () {
    final s = source('one', 1);
    expect(merge(incomingSources: [], incomingRows: [row(s, 1)]).canSave, false);
    expect(merge(incomingSources: [s], incomingRows: [
      {...row(s, 1), 'completion_source_message_id': 'missing'},
    ]).canSave, false);
  });

  test('allowance order is not a content conflict, changed allowance is', () {
    final a = source('a', 1), b = source('b', 1);
    final existing = {...row(a, 1), 'allowance_names': ['PC', '鉄骨']};
    final same = merge(targetSources: [a], targetRows: [existing],
      incomingSources: [b], incomingRows: [{...row(b, 1), 'allowance_names': ['鉄骨', 'PC']}]);
    expect(same.duplicateCount, 1);
    final changed = merge(targetSources: [a], targetRows: [existing],
      incomingSources: [b], incomingRows: [{...row(b, 1), 'allowance_names': ['PC']}]);
    expect(changed.conflictCount, 1);
  });

  test('malformed date never rolls into the selected month', () {
    final s = source('one', 1);
    final result = merge(incomingSources: [s], incomingRows: [{...row(s, 1), 'work_date': '2026-10-32'}]);
    expect(result.rows, isEmpty);
    expect(result.outOfMonthCount, 1);
  });

  test('unresolved identities never become a second counted copy by name alone', () {
    final a = source('a', 1), b = source('b', 1);
    final result = merge(targetSources: [a], targetRows: [row(a, 1)],
      incomingSources: [b], incomingRows: [{...row(b, 1), 'worker_id': null}]);
    expect(result.conflictCount, 1);
    expect(result.rows.last['excluded'], true);
    expect(result.rows.first['confirmed'], true);
  });

  test('refresh receiving a copy retains saved decisions and excludes the fresh copy', () {
    final a = source('a', 1), b = source('new-live', 1);
    final first = merge(incomingSources: [a], incomingRows: [row(a, 1)]);
    final retained = {...first.rows.single, 'review_reason': '確認済み'};
    final result = lineReconcileSavedMonthlyRows([
      {...retained, 'confirmed': false, 'review_reason': 'parser duplicate warning'}, row(b, 1),
    ], [retained]);
    expect(result.first, retained);
    expect(result.last['excluded'], true);
    expect(result.last['merge_duplicate_of'], retained['row_id']);
    final again = lineReconcileSavedMonthlyRows(result, result);
    expect(again, result);
  });

  test('refresh changed quantities wait for review without replacing saved quantities', () {
    final a = source('a', 1), b = source('correction', 1);
    final first = merge(incomingSources: [a], incomingRows: [row(a, 1, days: .5)]);
    final retained = first.rows.single;
    final result = lineReconcileSavedMonthlyRows([retained, row(b, 1)], [retained]);
    expect(result.first, retained);
    expect(result.last['excluded'], true);
    expect(result.last['merge_conflict_with'], [retained['row_id']]);
  });

  test('refresh does not alter unrelated live rows or other sites', () {
    final a = source('a', 1), b = source('b', 1), c = source('c', 1);
    final live = [row(a, 1), row(b, 1)];
    expect(lineReconcileSavedMonthlyRows(live, []), live);
    final saved = merge(incomingSources: [a], incomingRows: [row(a, 1)]).rows.single;
    final result = lineReconcileSavedMonthlyRows([saved, row(c, 1, site: 'site-b')], [saved]);
    expect(result.where((r) => r['excluded'] == true), isEmpty);
  });

  test('refresh preserves both preexisting saved decisions and source changes stay unconfirmed', () {
    final a = source('a', 1), b = source('b', 1);
    final saved = merge(incomingSources: [a], incomingRows: [row(a, 1)]).rows.single;
    final priorLive = row(b, 1, days: .5);
    final result = lineReconcileSavedMonthlyRows([
      {...saved, 'confirmed': false}, {...priorLive, 'confirmed': false},
    ], [saved, priorLive]);
    expect(result, [saved, priorLive]);
    final changed = {...saved, 'source_fingerprint': 'new-source', 'confirmed': false};
    expect(lineReconcileSavedMonthlyRows([changed, priorLive], [saved, priorLive]).first['confirmed'], false);
  });

  test('actual monthly extraction refresh retains original confirmed row after excluded saved-copy import', () {
    final a = source('live', 1), b = source('past-copy', 1), c = source('late-live-copy', 1);
    final refs = <Map<String, dynamic>>[{'id': 'worker-a', 'name': '山田'}];
    final sites = <Map<String, dynamic>>[{'id': 'site-a', 'name': '現場A'}];
    final first = merge(targetSources: [a], targetRows: [row(a, 1)],
      incomingSources: [b], incomingRows: [row(b, 1)]);
    final refreshed = lineMonthlyCandidates([...first.sources, c], DateTime(2026, 10),
      previous: first.rows, workers: refs, sites: sites);
    expect(refreshed.rows.singleWhere((r) => r['row_id'] == 'live:0'), first.rows.first);
    expect(refreshed.rows.where((r) => r['excluded'] != true), hasLength(1));
    expect(refreshed.rows.singleWhere((r) => r['row_id'] == 'late-live-copy:0')['excluded'], true);
  });

  test('copied completion evidence never borrows a same-name destination reporter', () {
    final start = source('past-start', 1, body: '10月1日\n現場A 山田');
    final ownEnd = source('past-end', 1, body: '現場A 定時',
      posted: '2026-10-01T08:02:00Z');
    final targetEnd = source('destination-end', 1, body: '現場A 残業２',
      posted: '2026-10-01T08:03:00Z');
    final previous = {...row(start, 1),
      'completion_source_message_id': ownEnd['id'],
      'completion_source_fingerprint': lineSourceFingerprint(ownEnd)};
    final merged = merge(incomingSources: [start, ownEnd], incomingRows: [previous]);
    final refreshed = lineMonthlyCandidates([...merged.sources, targetEnd], DateTime(2026, 10),
      previous: merged.rows, workers: [{'id': 'worker-a', 'name': '山田'}],
      sites: [{'id': 'site-a', 'name': '現場A'}]);
    expect(refreshed.rows.single, merged.rows.single);
    expect(refreshed.rows.single['completion_source_message_id'], 'saved:old-group:past-end');
    expect(refreshed.rows.single['completion_source_fingerprint'],
      lineSourceFingerprint(merged.sources.last));
    expect(refreshed.rows.single['confirmed'], true);

    final copiedStart = merged.sources.first;
    final unpaired = lineMonthlyCandidates([copiedStart, targetEnd], DateTime(2026, 10));
    expect(unpaired.rows.single['completion_source_message_id'], isNull);
    expect(unpaired.rows.single['man_days'], isNull);
  });

  test('nested saved sources retain their original completion boundary', () {
    final nested = {...source('nested-start', 1, body: '10月1日\n現場A 山田'),
      'saved_source_group_id': 'first-origin'};
    final nativeEnd = source('native-end', 1, body: '現場A 定時',
      posted: '2026-10-01T08:03:00Z');
    final merged = merge(incomingSources: [nested, nativeEnd], incomingRows: [row(nested, 1)]);
    expect(merged.sources.first['saved_source_origin_group_id'], 'first-origin');
    expect(merged.sources.last['saved_source_origin_group_id'], 'old-group');
    final extracted = lineMonthlyCandidates(merged.sources, DateTime(2026, 10));
    expect(extracted.rows.single['completion_source_message_id'], isNull);
    expect(extracted.rows.single['man_days'], isNull);
  });
}
