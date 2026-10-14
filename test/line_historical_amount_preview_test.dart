import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_amount_preview.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';

void main() {
  Map<String, dynamic> row({String site = 'A', double days = 1, double ot = 0}) => {
    'site_name': site, 'work_category': 'day', 'man_days': days,
    'overtime_hours': ot, 'early_hours': 0, 'allowance_names': <String>[],
    'confirmed': false,
  };
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
}
