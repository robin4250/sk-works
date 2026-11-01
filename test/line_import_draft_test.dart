import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';

void main() {
  final month = DateTime(2026, 10);
  Map<String, dynamic> source(String body, [String id = 'post-one']) => {
    'id': id, 'body': body, 'sent_at': '2026-10-01T00:00:00Z', 'sender_display_name': '投稿者',
  };
  test('January reports of December work retain the work year and explicit years', () {
    final post = {...source('12月31日\n現場A 山田\n現場A 定時'),
      'sent_at': '2027-01-02T00:00:00Z'};
    expect(LineImportDraft.extract([post], DateTime(2026, 12)).rows.single['work_date'],
      '2026-12-31');
    expect(LineImportDraft.extract([post], DateTime(2027, 1)).rows, isEmpty);
    final explicit = {...post, 'body': '2027年12月31日\n現場A 山田\n現場A 定時'};
    expect(LineImportDraft.extract([explicit], DateTime(2027, 12)).rows.single['work_date'],
      '2027-12-31');
  });
  test('extracts explicit date/site/workers and status without automatically confirming identities', () {
    final result = LineImportDraft.extract([source('10月1日\n現場A 山田、佐藤\n現場A 定時 残業1 早出0.5 鉄骨')], month);
    expect(result.rows, hasLength(2));
    expect(result.rows.first['work_date'], '2026-10-01');
    expect(result.rows.first['man_days'], 1);
    expect(result.rows.first['overtime_hours'], 1);
    expect(result.rows.first['early_hours'], .5);
    expect(result.rows.first['steel_allowance'], isTrue);
    expect(result.rows.first['worker_id'], isNull);
    expect(result.rows.first['confirmed'], isFalse);
  });
  test('inline explicit overtime and early hours retain source and remain unconfirmed', () {
    for (final entry in [
      ('残業１', 1.0, 0.0), ('残業3', 3.0, 0.0),
      ('残業３', 3.0, 0.0), ('残業1.5', 1.5, 0.0),
      ('早出０．５', 0.0, .5), ('残業１ 早出0.5', 1.0, .5),
    ]) {
      final original = source('10/15\n新宿 佐藤 ${entry.$1}');
      final result = LineImportDraft.extract([original], month);
      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row['site_name'], '新宿');
      expect(row['worker_name'], '佐藤');
      expect(row['overtime_hours'], entry.$2);
      expect(row['early_hours'], entry.$3);
      expect(row['confirmed'], isFalse);
      expect(row['source_message_id'], original['id']);
      expect(original['body'], '10/15\n新宿 佐藤 ${entry.$1}');
      final edited = {...row, 'overtime_hours': 2.0, 'confirmed': true};
      expect(LineImportDraft.extract([original], month, previous: [edited]).rows.single,
          edited);
    }
  });
  test('status-only and correction lines never become workers', () {
    for (final line in ['新宿 残業１', '新宿 早出1', '訂正 新宿 佐藤 残業1']) {
      expect(LineImportDraft.extract([source('10/15\n$line')], month).rows, isEmpty);
    }
  });
  test('distinct worker overtime at the same site is not guessed as shared hours', () {
    final result = LineImportDraft.extract([
      source('10/15\n新宿 佐藤 残業1\n新宿 田中 残業3'),
    ], month);
    expect(result.rows, hasLength(2));
    expect(result.rows.every((r) => r['confirmed'] == false), isTrue);
    expect(result.rows.every((r) => r['overtime_hours'] == 0), isTrue);
  });
  test('same source preserves corrections during reimport; changed source needs review', () {
    final original = source('10月1日\n現場A 山田\n現場A 定時');
    final initial = LineImportDraft.extract([original], month);
    final edited = {...initial.rows.single, 'worker_id': 'worker-one', 'man_days': .5, 'confirmed': true};
    final stable = LineImportDraft.extract([original], month, previous: [edited]);
    expect(stable.rows.single['man_days'], .5);
    expect(stable.rows.single['confirmed'], isTrue);
    final changed = LineImportDraft.extract([source('10月1日\n現場A 山田\n現場A 定時 残業1')], month, previous: [edited]);
    expect(changed.rows.single['confirmed'], isFalse);
    expect(changed.rows.single['review_reason'], contains('元の投稿が変わりました'));
  });
  test('impossible date and full-width impossible date are never rolled into next month', () {
    for (final date in ['2026年2月30日', '２０２６年２月３０日']) {
      final result = LineImportDraft.extract([source('$date\n現場A 山田\n現場A 定時')], DateTime(2026, 3));
      expect(result.rows, isEmpty);
      expect(result.unreadableSourceIds, ['post-one']);
    }
  });
  test('different sites on one day remain distinct without a false duplicate warning', () {
    final result = LineImportDraft.extract([source('10月1日\n現場A 山田\n現場A 定時'), source('10月1日\n現場B 山田\n現場B 定時', 'post-two')], month);
    expect(result.rows, hasLength(2));
    expect(result.rows.every((row) => row['confirmed'] == false), isTrue);
    expect(result.rows.any((row) => row['review_reason'].toString().contains('複数行')), isFalse);
  });
  test('selected month only and unreadable messages are reported', () {
    final result = LineImportDraft.extract([source('9月30日\n現場A 山田\n現場A 定時'), source('おはようございます', 'greeting')], month);
    expect(result.rows, isEmpty);
    expect(result.unreadableSourceIds, ['greeting']);
  });
  test('monthly totals contain only confirmed included rows and use stable identities', () {
    final rows = [
      {'worker_id': 'one', 'worker_name': '山田', 'site_id': 'site', 'site_name': '現場A', 'confirmed': true, 'man_days': 1, 'overtime_hours': 1, 'early_hours': .5},
      {'worker_id': 'one', 'worker_name': '山田', 'site_id': 'site', 'site_name': '現場A', 'confirmed': true, 'man_days': .5, 'overtime_hours': .5, 'early_hours': 0},
      {'worker_id': 'one', 'confirmed': true, 'excluded': true, 'man_days': 100},
      {'worker_id': 'one', 'confirmed': false, 'man_days': 100},
    ];
    final result = LineImportDraft.aggregate(rows, bySite: false);
    expect(result, hasLength(1));
    expect(result.single['man_days'], 1.5);
    expect(result.single['overtime_hours'], 1.5);
    expect(result.single['early_hours'], .5);
    expect(result.single['rows'], 2);
  });
}
