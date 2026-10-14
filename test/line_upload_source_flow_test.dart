import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_history_parser.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';
import 'package:sk_works/domain/rate_formula_settings.dart';

void main() {
  test('quoted export is read without replacing original evidence', () {
    final body = '\"9月30日（水）\n現場A 作業員A、作業員B\n現場A 定時\"';
    final source = <String, dynamic>{
      'id': 'example', 'body': body, 'sent_at': '2026-10-02T06:00:00+09:00',
      'sender_display_name': '報告者', 'source_type': 'history',
    };
    final draft = LineImportDraft.extract([source], DateTime(2026, 9));
    expect(draft.rows, hasLength(2));
    expect(draft.rows.first['work_date'], '2026-09-30');
    expect(draft.rows.first['man_days'], 1);
    expect(draft.rows.first['confirmed'], false);
    expect(source['body'], body);
    expect(draft.rows.first['source_fingerprint'], lineSourceFingerprint(source));
  });
  test('all supplied earlier months remain selectable', () {
    final months = lineHistoryMonthsForSources([
      {'sent_at': '2019-10-02T06:00:00+09:00'},
      {'sent_at': '2026-10-14T06:00:00+09:00'},
    ]);
    expect(months.first, DateTime(2019, 10));
    expect(months.contains(DateTime(2026, 9)), true);
    expect(months.contains(DateTime(2026, 10)), true);
  });
  test('initial overtime follows the SKO calculation', () {
    expect(const RateFormulaSettings().overtime(32800), 5125);
    expect(const RateFormulaSettings().overtime(32000), 5000);
    expect(lineBodyForReading('通常の本文'), '通常の本文');
  });
}
