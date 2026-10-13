import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iPhone acceptance test covers final integrated modules', () {
    final doc = File('docs/IPHONE_ACCEPTANCE_TEST.md').readAsStringSync();

    expect(doc, contains('## M. 現場チャット連動'));
    expect(doc, contains('## N. 車両・ルート'));
    expect(doc, contains('## O. Master管理'));
    expect(doc, contains('15分'));
    expect(doc, contains('個別情報が表示されない'));
    expect(doc, contains('車両・ルート'));
    expect(doc, contains('GPS自動出勤'));
    expect(doc, contains('指定時刻の前後5分'));
    expect(doc, contains('メーターを撮影して読取'));
    expect(doc, contains('## J2. 社員個人ページ・一覧印刷'));
    expect(doc, contains('A4横向き'));
    expect(doc, contains('日本の祝日の日付と祝日名が赤く表示される'));
    expect(doc, contains('月間カレンダーの◁/▷'));
    expect(doc, contains('## J3. 給与管理フロー'));
    expect(doc, contains('個別給与設定 → 給与調整 → 給与明細 → プレビュー → 印刷'));
    expect(doc, contains('## P. 会社間送受信・協力会社'));
    expect(doc, contains('## Q. 現場詳細・現場マップ'));
  });
}
