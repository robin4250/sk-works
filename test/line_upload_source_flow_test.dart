import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_history_parser.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';
import 'package:sk_works/domain/rate_formula_settings.dart';

void main() {
  test('quoted export is read without replacing original evidence', () {
    final body = '"9月30日（水）\n現場A 作業員A、作業員B\n現場A 定時"';
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
  test('separate same-sender completion retains both original messages', () {
    final sources = [
      <String, dynamic>{'id': 'plan', 'body': '9月30日（水）\n現場A 作業員A、作業員B', 'sent_at': '2026-10-02T06:00:00+09:00', 'sender_display_name': '報告者'},
      <String, dynamic>{'id': 'end', 'body': '現場A 定時', 'sent_at': '2026-10-02T06:01:00+09:00', 'sender_display_name': '報告者'},
    ];
    final result = lineMonthlyCandidates(sources, DateTime(2026, 9));
    expect(result.rows, hasLength(2));
    expect(result.rows.first['man_days'], 1);
    expect(result.rows.first['completion_source_message_id'], 'end');
    expect(result.sources.map((s) => s['id']), containsAll(['plan', 'end']));
    final corrected = {...result.rows.first, 'confirmed': true};
    sources[1]['body'] = '現場A 残業2';
    final changed = lineMonthlyCandidates(sources, DateTime(2026, 9), previous: [corrected]);
    expect(changed.rows.first['confirmed'], false);
    expect(changed.rows.first['overtime_hours'], 2);
  });
  test('other sender completion cannot set quantities', () {
    final draft = LineImportDraft.extract([
      {'id': 'plan', 'body': '9月30日\n現場A 作業員A', 'sent_at': '2026-10-02T06:00:00+09:00', 'sender_display_name': 'A'},
      {'id': 'end', 'body': '現場A 定時', 'sent_at': '2026-10-02T06:01:00+09:00', 'sender_display_name': 'B'},
    ], DateTime(2026, 9));
    expect(draft.rows.single['man_days'], isNull);
  });
  test('all supplied earlier months remain selectable' , () {
    final months = lineHistoryMonthsForSources([
      {'sent_at': '2019-10-02T06:00:00+09:00'},
      {'sent_at': '2026-10-14T06:00:00+09:00'},
    ]);
    expect(months.first, DateTime(2019, 10));
    expect(months.contains(DateTime(2026, 9)), true);
    expect(months.contains(DateTime(2026, 10)), true);
  });
  test('cancellation events do not corrupt quoted message boundaries', () {
    final parsed = const LineHistoryParser().parse('2026/10/02(金)\n06:00\tA\t"9月30日\n現場A 作業員A"\n06:01\t\t送信を取り消しました');
    expect(parsed.messages, hasLength(1));
    expect(lineBodyForReading(parsed.messages.single.body), '9月30日\n現場A 作業員A');
    expect(parsed.ignoredLineCount, 1);
  });
  test('initial overtime follows the SKO calculation', () {
    expect(const RateFormulaSettings().overtime(32800), 5125);
    expect(const RateFormulaSettings().overtime(32000), 5000);
    expect(lineBodyForReading('通常の本文'), '通常の本文');
  });
}
