import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/help/manual_content.dart';
import 'package:sk_works/features/help/manual_library_page.dart';

void main() {
  testWidgets('contents opens only its selected feature with chapter PDF entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ManualLibraryPage(role: ManualRole.general)));
    final first = ManualContent.general.first;
    final entry = find.widgetWithText(ListTile, first.title).first;
    await tester.scrollUntilVisible(entry, 200);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ManualChapterPage), findsOneWidget);
    expect(find.text('この機能のPDFを開く'), findsOneWidget);
    expect(find.text(first.support), findsOneWidget);
    expect(find.text(ManualContent.general[1].title), findsNothing);
  });

  testWidgets('brochure contents shares the same feature reader and PDF entry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ManualLibraryPage(role: ManualRole.general)));
    final contents = find.text('パンフレットの機能別目次');
    await tester.scrollUntilVisible(contents, 200);
    await tester.tap(contents);
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(ListTile, ManualContent.pamphlet.first.title);
    await tester.scrollUntilVisible(entry, 200);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ManualChapterPage), findsOneWidget);
    expect(find.text('この機能のPDFを開く'), findsOneWidget);
    expect(find.text(ManualContent.pamphlet.first.support), findsOneWidget);
  });

  test('role sections keep existing order and append new features', () {
    expect(ManualContent.general[9].title, 'プロフィール・ヘルプ・印刷');
    expect(ManualContent.subAdmin[10].title, 'サブ管理者の役割');
    expect(ManualContent.admin[10].title, '管理者の役割');
    expect(ManualContent.pamphlet[19].title, 'ベータ版と実機確認');
    for (final sections in [ManualContent.general, ManualContent.subAdmin,
      ManualContent.admin, ManualContent.pamphlet]) {
      expect(sections.map((section) => section.title).toSet().length, sections.length);
      expect(sections.map((section) => section.title), contains('天気・交通とホームの並べ替え'));
    }
    expect(ManualContent.general.map((section) => section.title),
      isNot(contains('LINEトークと月別請求書')));
    expect(ManualContent.admin.map((section) => section.title),
      contains('LINEトークと月別請求書'));
  });
}
