import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/help/manual_version.dart';
import 'package:sk_works/features/help/menu_help_catalog.dart';

void main() {
  test('every published help feature maps to current chapters and real sources', () {
    final inventory = jsonDecode(File('docs/manual_feature_coverage.json').readAsStringSync()) as Map<String, dynamic>;
    expect(inventory['revision_date'], ManualVersion.revisionDate);
    final rows = (inventory['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final keys = rows.map((row) => row['key'] as String).toList();
    expect(keys.toSet().length, keys.length);
    expect(keys.toSet(), MenuHelpCatalog.items.map((item) => item.key).toSet());
    final chapters = [for (final role in ManualRole.values) ...ManualContent.forRole(role), ...ManualContent.pamphlet].map((section) => section.title).toSet();
    for (final row in rows) {
      expect(row['chapters'] as List<dynamic>, isNotEmpty);
      expect(row['sources'] as List<dynamic>, isNotEmpty);
      for (final chapter in row['chapters'] as List<dynamic>) {
        expect(chapters, contains(chapter), reason: '${row['key']} links to a missing chapter.');
      }
      for (final source in row['sources'] as List<dynamic>) {
        expect(File(source as String).existsSync(), isTrue, reason: 'Missing reference source for ${row['key']}');
      }
    }
  });

  test('manuals distinguish read-only candidates and formal LINE confirmation', () {
    final readOnly = ManualContent.admin.singleWhere((section) => section.title == '本日のLINE出勤候補を確認する');
    expect(readOnly.support, contains('正式な勤怠保存を行いません'));
    final formal = ManualContent.admin.singleWhere((section) => section.title == 'LINE出勤表・請求書の確認と申請');
    expect(formal.steps.join(' '), contains('署名して出勤を申請'));
    expect(formal.support, contains('マスター設定と既存権限'));
  });

  test('manual role guides preserve permission-based payroll settings and admin adjustments', () {
    for (final role in ManualRole.values) {
      final titles = ManualContent.forRole(role).map((section) => section.title);
      expect(titles, contains('本人の経費申請と領収書'));
      expect(titles, contains('ノートの作成・検索・ピン留め'));
      expect(titles, contains('アルバムの作成・写真の追加'));
      expect(titles, contains('ルート勤務の現場到着・現場移動'));
    }
    expect(ManualContent.general.map((section) => section.title),
      isNot(contains('個別給与設定の確認・登録')));
    expect(ManualContent.subAdmin.map((section) => section.title),
      contains('個別給与設定の確認・登録'));
    expect(ManualContent.subAdmin.map((section) => section.title),
      isNot(contains('給与調整の対象日と登録・修正')));
    expect(ManualContent.admin.map((section) => section.title),
      contains('給与調整の対象日と登録・修正'));
    expect(ManualContent.subAdmin.singleWhere((section) =>
      section.title == '個別給与設定の確認・登録').support,
      contains('閲覧と編集の権限は別'));

  });
}
