import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_amount_preview.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';
import 'package:sk_works/features/chat/line_saved_monthly_merge.dart';

void main() {
  Map<String, dynamic> post(int day, String prefix) => {
    'id': '$prefix-$day',
    'body': '10月$day日\n現場A 山田\n現場A 定時',
    'sent_at': '2026-11-01T08:00:00Z',
    'sender_display_name': '担当者', 'source_type': 'received',
  };
  final workers = <Map<String, dynamic>>[{'id': 'worker', 'name': '山田'}];
  final sites = <Map<String, dynamic>>[{'id': 'site', 'name': '現場A'}];
  final month = DateTime(2026, 10);

  test('saved merge and live refresh feed one monthly table and reference invoice', () {
    final old = [for (var day = 1; day <= 7; day++) post(day, 'old')];
    final live = [for (var day = 8; day <= 20; day++) post(day, 'live')];
    final oldRows = lineMonthlyCandidates(old, month, workers: workers, sites: sites).rows;
    final liveRows = lineMonthlyCandidates(live, month, workers: workers, sites: sites).rows;
    final corrected = [for (final row in liveRows) {...row, 'confirmed': true}];
    final merge = linePreviewSavedMonthlyMerge(month: month, sourceGroupId: 'old-group',
      targetSources: live, targetRows: corrected,
      incomingSources: old, incomingRows: oldRows);
    expect(merge.addedCount, 7);
    final refreshed = lineMonthlyCandidates([...merge.sources, post(30, 'live')], month,
      previous: merge.rows, workers: workers, sites: sites);
    expect(refreshed.rows.where((r) => r['excluded'] != true), hasLength(21));
    for (final before in corrected) {
      expect(refreshed.rows.singleWhere((r) => r['row_id'] == before['row_id']), before);
    }
    final amount = lineHistoricalAmountPreview(refreshed.rows);
    expect(amount.includedRows, 21);
    expect(amount.workDates.first, '2026-10-01');
    expect(amount.workDates.last, '2026-10-30');
    expect(amount.workDates, containsAll(['2026-10-07', '2026-10-08', '2026-10-20']));
    expect(amount.invoice(month).grandTotalYen, amount.total);
    expect(amount.invoice(month).invoiceNumber, '参考・未確認');
    final repeated = linePreviewSavedMonthlyMerge(month: month, sourceGroupId: 'old-group',
      targetSources: refreshed.sources, targetRows: refreshed.rows,
      incomingSources: old, incomingRows: oldRows);
    expect(repeated.addedCount, 0);
    expect(repeated.duplicateCount, 7);
    expect(lineHistoricalAmountPreview(repeated.rows).total, amount.total);
    expect(repeated.rows, refreshed.rows);
    expect(old.every((s) => s['source_type'] == 'received'), isTrue);
  });
}
