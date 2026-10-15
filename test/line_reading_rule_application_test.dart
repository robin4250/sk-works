import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/line_historical_monthly_import.dart';
import 'package:sk_works/features/chat/line_import_draft.dart';
import 'package:sk_works/features/chat/line_reading_rules.dart';
import 'package:sk_works/features/chat/line_reading_rule_application.dart';

void main() {
  final month = DateTime(2026, 10);
  Map<String, dynamic> source(String lines) => {
    'id':'post', 'body':'10/15\n$lines', 'sent_at':'2026-10-15T08:00:00Z',
    'sender_display_name':'投稿者',
  };
  test('explicit inline and separate hours stay real; missing hours carry structured estimates', () {
    for (final body in ['新宿 佐藤 残業１', '新宿 佐藤\n新宿 残業１']) {
      final row = lineMonthlyCandidates([source(body)], month).rows.single;
      expect(row['overtime_hours'], 1);
      expect(lineHasAssumedQuantities(row), false);
    }
    for (final body in ['新宿 佐藤 残業 早出', '新宿 佐藤\n新宿 残業 早出']) {
      final original = source(body);
      final row = lineMonthlyCandidates([original], month).rows.single;
      expect(row['overtime_hours'], 1);
      expect(row['early_hours'], 1);
      expect(lineAssumedFields(row).keys.toSet(), {'overtime_hours','early_hours'});
      expect((lineAssumedFields(row)['overtime_hours'] as Map)['reason'], contains('記載がない'));
      expect(row['confirmed'], false);
      expect(original['body'], '10/15\n$body');
      final stored = Map<String,dynamic>.from(jsonDecode(jsonEncode(row)) as Map);
      expect(lineAssumedFields(stored), lineAssumedFields(row));
      final repaired = lineRepairAssumedQuantity(stored, 'overtime_hours', 3);
      expect(repaired['overtime_hours'], 3);
      expect(repaired['early_hours'], 1);
      expect(lineAssumedFields(repaired).keys, ['early_hours']);
      expect(repaired['confirmed'], false);
      expect(repaired['source_fingerprint'], row['source_fingerprint']);
      expect(LineImportDraft.aggregate([{...repaired, 'confirmed':true, 'worker_id':'w'}], bySite:false), isEmpty);
    }
  });
  test('custom hour labels, allowance and exact category apply to only their row', () {
    final rows = lineMonthlyCandidates([source('新宿 佐藤 OT３ PC 深夜\n渋谷 田中')], month,
      readingRules: const [
        LineReadingRule(phrase:'OT',kind:LineReadingKind.overtime,value:'overtime_hours'),
        LineReadingRule(phrase:'PC',kind:LineReadingKind.allowance,value:'PC手当'),
        LineReadingRule(phrase:'深夜',kind:LineReadingKind.workCategory,value:'night'),
      ]).rows;
    final sato = rows.singleWhere((r) => r['worker_name'] == '佐藤');
    final tanaka = rows.singleWhere((r) => r['worker_name'] == '田中');
    expect(sato['overtime_hours'], 3);
    expect(sato['allowance_names'], contains('PC手当'));
    expect(sato['work_category'], 'night');
    expect(tanaka['overtime_hours'], 0);
    expect(tanaka['allowance_names'], isEmpty);
    expect(tanaka['work_category'], 'day');
  });
  test('different workers keep individual hours; ambiguous repeated reports stay unresolved', () {
    final rows = lineMonthlyCandidates([source('新宿 佐藤 残業1\n新宿 田中 残業3')], month).rows;
    expect(rows.singleWhere((r) => r['worker_name'] == '佐藤')['overtime_hours'], 1);
    expect(rows.singleWhere((r) => r['worker_name'] == '田中')['overtime_hours'], 3);
    final ambiguous = lineMonthlyCandidates([source('新宿 佐藤\n新宿 残業1\n新宿 残業3')], month).rows.single;
    expect(ambiguous['overtime_hours'], 0);
    expect(ambiguous['confirmed'], false);
  });
  test('ignored token does not delete unrelated rows; unknown category is not guessed', () {
    final rows = lineMonthlyCandidates([source('新宿 佐藤 了解\n渋谷 田中 仮区分')], month,
      readingRules: const [
        LineReadingRule(phrase:'了解',kind:LineReadingKind.ignore,value:'対象外'),
        LineReadingRule(phrase:'仮区分',kind:LineReadingKind.workCategory,value:'不明'),
      ]).rows;
    expect(rows.map((r) => r['worker_name']).toSet(), {'佐藤','田中'});
    expect(rows.every((r) => r['excluded'] != true), true);
    expect(rows.every((r) => r['work_category'] == 'day'), true);
  });
  test('reimport preserves saved repairs and assumptions without re-estimating', () {
    final original = source('新宿 佐藤 残業 早出');
    final row = lineMonthlyCandidates([original], month).rows.single;
    final repaired = lineRepairAssumedQuantity(row, 'overtime_hours', 2.5);
    final next = lineMonthlyCandidates([original], month, previous:[repaired]).rows.single;
    expect(next, repaired);
  });
}
