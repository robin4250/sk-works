import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';

void main() {
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
