import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_amount_preview.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';

void main() {
  Map<String, dynamic> row({String site = 'A', double days = 1, double ot = 0}) => {
    'site_name': site, 'work_category': 'day', 'man_days': days,
    'overtime_hours': ot, 'early_hours': 0, 'allowance_names': <String>[],
    'confirmed': false,
  };
  test('calculated dates and count use precisely the reference amount rows', () {
    final result = lineHistoricalAmountPreview([
      {...row(), 'work_date': '2026-10-01'},
      {...row(), 'work_date': '2026-10-20'},
      {...row(site: 'B'), 'work_date': '2026-10-20'},
      {...row(), 'work_date': '2026-10-30', 'excluded': true},
      {...row(), 'work_date': '2026-10-07', 'man_days': null},
    ]);
    expect(result.workDates, ['2026-10-01', '2026-10-20']);
    expect(result.includedRows, 3);
    expect(result.incompleteRows, 1);
  });
  test('specified daily overtime and allowances produce per-site invoice estimate', () {
    final result = lineHistoricalAmountPreview([
      {...row(ot: 2), 'allowance_names': ['PC', 'PC手当', '鉄骨手当']},
    ]);
    expect(result.sites.single.base, 49050);
    expect(result.sites.single.welfare, 7358);
    expect(result.sites.single.tax, 5641);
    expect(result.total, 62049);
    expect(result.pendingRows, 1);
    expect(result.incompleteRows, 0);
    final invoice = result.invoice(DateTime(2026, 9));
    expect(invoice.grandTotalYen, result.total);
    expect(invoice.siteCalculations.single.lines.map((line) => line.label), containsAll(['残業', 'PC手当', '鉄骨手当']));
    expect(invoice.invoiceId, isEmpty);
    expect(invoice.invoiceNumber, '参考・未確認');
  });
  test('unknown quantity, allowance or duplicate is excluded rather than priced at zero', () {
    final result = lineHistoricalAmountPreview([
      {...row(), 'man_days': null},
      {...row(), 'allowance_names': ['未設定手当']},
      {...row(), 'review_reason': '同日の作業員が複数行あります。'},
      {...row(), 'steel_allowance': true},
      {...row(), 'excluded': true},
    ]);
    expect(result.sites, isEmpty);
    expect(result.incompleteRows, 4);
    expect(result.pendingRows, 4);
  });
  test('round category totals before site welfare and tax, and recalculate edits', () {
    final first = row(days: .5, ot: .1);
    final second = row(days: .5, ot: .1);
    final result = lineHistoricalAmountPreview([first, second, row(site: 'B')]);
    expect(result.sites.first.base, 33825);
    expect(result.sites.last.total, 41492);
    first['man_days'] = 1;
    expect(lineHistoricalAmountPreview([first, second]).total, greaterThan(result.sites.first.total));
  });
  test('explicit steel completion flows into the calculated allowance quantity', () {
    final draft = LineImportDraft.extract([
      {'id': 'plan', 'body': '9月1日\n現場A 作業員A', 'sent_at': '2026-09-01T06:00:00+09:00', 'sender_display_name': '報告者'},
      {'id': 'end', 'body': '現場A 定時〈鉄骨〉', 'sent_at': '2026-09-01T17:00:00+09:00', 'sender_display_name': '報告者'},
    ], DateTime(2026, 9));
    expect(draft.rows.single['allowance_names'], ['鉄骨手当']);
    expect(lineHistoricalAmountPreview(draft.rows).sites.single.base, 35800);
  });
  test('night and holiday reference rates follow the existing SKO formulas', () {
    expect(lineHistoricalDefaultDayRate('night'), 49200);
    expect(lineHistoricalDefaultDayRate('holiday'), 44280);
    final preview = lineHistoricalAmountPreview([{...row(ot: 1), 'work_category': 'night'}]);
    expect(preview.sites.single.base, 56888);
    expect(preview.invoice(DateTime(2026, 9)).grandTotalYen, preview.total);
  });
  test('identical completion posts in one minute remain attached to different plans', () {
    final sources = lineHistorySources('2026/09/28(月)\n06:24\t報告者\t"9月22日\n現場A 作業員A"\n06:24\t報告者\t現場A 定時\n06:24\t報告者\t"9月23日\n現場A 作業員A"\n06:24\t報告者\t現場A 定時');
    expect(sources, hasLength(4));
    final rows = lineMonthlyCandidates(sources, DateTime(2026, 9)).rows;
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['man_days']), everyElement(1));
    expect(rows.map((row) => row['completion_source_message_id']).toSet(), hasLength(2));
  });
  test('night suffix on a work date is retained in the monthly calculation', () {
    final sources = lineHistorySources('2026/09/28(月)\n06:22\t報告者\t"9月21日（月）夜勤\n現場A 作業員A"\n06:22\t報告者\t現場A 定時〈夜勤〉');
    final rows = lineMonthlyCandidates(sources, DateTime(2026, 9)).rows;
    expect(rows.single['work_category'], 'night');
    expect(lineHistoricalAmountPreview(rows).sites.single.base, 49200);
  });
  test('overtime completion gives an explicitly unconfirmed one-day assumption', () {
    final rows = LineImportDraft.extract([
      {'id': 'source', 'body': '9月1日\n現場A 作業員A\n現場A 残業2', 'sent_at': '2026-09-01T17:00:00+09:00', 'sender_display_name': '報告者'},
    ], DateTime(2026, 9)).rows;
    expect(rows.single['man_days'], 1);
    expect(rows.single['man_days_inferred'], true);
    expect(rows.single['confirmed'], false);
    expect(lineHistoricalAmountPreview(rows).sites.single.base, 43050);
  });
}
