import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';

void main() {
  test('received and exported copies count once and retain the saved history correction', () {
    const body = '9月1日\n現場A 山田\n現場A 定時';
    final history = <String, dynamic>{
      'id': 'history-copy', 'body': body, 'sent_at': '2026-09-01T08:10:00Z',
      'sender_display_name': '投稿者', 'source_type': 'history',
    };
    final received = <String, dynamic>{
      ...history, 'id': 'received-copy', 'source_type': 'received',
      'sent_at': '2026-09-01T08:10:20Z',
    };
    final initial = lineMonthlyCandidates([history], DateTime(2026, 9));
    final corrected = {...initial.rows.single, 'man_days': .5, 'confirmed': true};
    final merged = lineMonthlyCandidates([history, received], DateTime(2026, 9),
      previous: [corrected]);
    expect(merged.sources, hasLength(2));
    expect(merged.rows, hasLength(1));
    expect(merged.rows.single['source_message_id'], 'history-copy');
    expect(merged.rows.single['man_days'], .5);
    expect(merged.rows.single['confirmed'], true);
    final firstImport = lineMonthlyCandidates([history, received], DateTime(2026, 9));
    expect(firstImport.rows.single['source_message_id'], 'received-copy');
    expect(firstImport.rows.single['confirmed'], false);
  });
  test('ambiguous repeated received posts are retained for review', () {
    final base = <String, dynamic>{
      'body': '9月1日\n現場A 山田\n現場A 定時',
      'sent_at': '2026-09-01T08:10:00Z', 'sender_display_name': '投稿者',
    };
    final result = lineMonthlyCandidates([
      {...base, 'id': 'one', 'source_type': 'received'},
      {...base, 'id': 'two', 'source_type': 'received'},
      {...base, 'id': 'history', 'source_type': 'history'},
    ], DateTime(2026, 9));
    expect(result.rows, hasLength(3));
    expect(result.rows.every((row) => row['confirmed'] == false), isTrue);
  });

  test('supplement window includes October without dropping the 33 original months', () {
    final months = lineHistoryImportMonths(through: DateTime(2026, 10, 14));
    expect(months, hasLength(34));
    expect(months.first, DateTime(2024, 1));
    expect(months.last, DateTime(2026, 10));
    expect(months.take(33), lineHistoricalMonths());
  });
  test('overlapping file supplements preserve old corrections and deduplicate posts', () {
    final earlier = lineHistorySources(
      '2026/09/01\n08:10\t投稿者\t9月1日\n現場A 山田\n現場A 定時');
    final extra = lineHistorySources(
      '2026/09/02\n08:10\t投稿者\t9月2日\n現場A 山田\n現場A 定時');
    final initial = lineMonthlyCandidates(earlier, DateTime(2026, 9));
    final corrected = {...initial.rows.single, 'man_days': .5, 'confirmed': true};
    final merged = lineMergeImportSources(earlier, [...earlier, ...extra]);
    expect(merged, hasLength(2));
    final supplemented = lineMonthlyCandidates(merged, DateTime(2026, 9),
      previous: [corrected]);
    expect(supplemented.rows, hasLength(2));
    final retained = supplemented.rows.singleWhere(
      (row) => row['source_message_id'] == earlier.single['id']);
    expect(retained['man_days'], .5);
    expect(retained['confirmed'], true);
    final oct = lineHistorySources(
      '2026/10/01\n08:10\t投稿者\t10月1日\n現場A 山田\n現場A 定時');
    expect(lineMonthlyCandidates(oct, DateTime(2026, 9)).sources, isEmpty);
    expect(lineMonthlyCandidates(oct, DateTime(2026, 10)).rows, hasLength(1));
  });
  test('explicit month replacement retains received evidence', () {
    final rows = lineMergeImportSources([
      {'id': 'old', 'source_type': 'history'},
      {'id': 'received', 'source_type': 'received'},
    ], [{'id': 'new', 'source_type': 'history'}], replaceHistory: true);
    expect(rows.map((row) => row['id']), ['received', 'new']);
  });

  test('33 historical months include January 2024 and September 2026', () {
    final months = lineHistoricalMonths();
    expect(months, hasLength(33));
    expect(months.first, DateTime(2024, 1));
    expect(months.last, DateTime(2026, 9));
    expect(months.toSet(), hasLength(33));
  });
  test('file reimport retains identities and corrections without auto-confirming new rows', () {
    const text = '2026/09/01\n08:10\t投稿者\t9月1日\n現場A 山田\n現場A 定時\n'
      '2026/10/01\n08:10\t投稿者\t10月1日\n現場A 山田\n現場A 定時';
    final history = lineHistorySources(text);
    expect(lineHistorySources(text).map((s) => s['id']), history.map((s) => s['id']));
    final initial = lineMonthlyCandidates(history, DateTime(2026, 9),
      workers: [{'id': 'worker', 'name': '山田'}],
      sites: [{'id': 'site', 'name': '現場A', 'customer_id': 'customer'}]);
    expect(initial.rows, hasLength(1));
    expect(initial.sources, hasLength(1));
    expect(initial.rows.single['worker_id'], 'worker');
    expect(initial.rows.single['site_id'], 'site');
    expect(initial.rows.single['confirmed'], false);
    final corrected = {...initial.rows.single, 'man_days': .5, 'confirmed': true};
    final repeated = lineMonthlyCandidates(history, DateTime(2026, 9), previous: [corrected]);
    expect(repeated.rows.single['man_days'], .5);
    expect(repeated.rows.single['confirmed'], true);
  });
  test('a post in next month still supplies evidence for its explicit work date', () {
    final history = lineHistorySources(
      '2026/10/01\n08:10\t投稿者\t9月30日\n現場A 山田\n現場A 定時');
    final result = lineMonthlyCandidates(history, DateTime(2026, 9));
    expect(result.rows.single['work_date'], '2026-09-30');
    expect(result.sources.single['id'], result.rows.single['source_message_id']);
  });
  test('ambiguous worker or site names stay unresolved', () {
    final history = lineHistorySources(
      '2026/09/01\n08:10\t投稿者\t9月1日\n現場A 山田\n現場A 定時');
    final result = lineMonthlyCandidates(history, DateTime(2026, 9),
      workers: [{'id': 'one', 'name': '山田'}, {'id': 'two', 'name': '山田'}]);
    expect(result.rows.single['worker_id'], isNull);
    expect(result.rows.single['confirmed'], false);
  });
  test('invoice name comes from saved historical rates, never current site metadata', () {
    expect(lineHistoricalFormalSiteName({'lines': [
      {'site_id': 'site', 'rates': {'site_name': '正式現場名'}},
      {'site_id': 'other', 'rates': {'site_name': '別の現場'}},
    ]}, 'site'), '正式現場名');
    expect(lineHistoricalFormalSiteName({'lines': [
      {'site_id': 'site', 'rates': {'site_name': '名称A'}},
      {'site_id': 'site', 'rates': {'site_name': '名称B'}},
    ]}, 'site'), isNull);
    expect(lineHistoricalFormalSiteName({'lines': [
      {'site_id': 'site', 'rates': {'day': 18000}},
    ]}, 'site'), isNull);
  });
}
