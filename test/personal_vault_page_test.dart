import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/personal_vault/personal_vault_page.dart';
void main() {
 testWidgets('only read actions, owned receipt ID and retry keep errors visible', (t) async {
  var requests=0; final opened=<String>[];
  await t.pumpWidget(MaterialApp(home: PersonalVaultPage(loadMine: () async {
   requests++;if(requests==1) { throw StateError('fixture error'); }
   return [const PersonalVaultEntry(id:'own-receipt',label:'給与明細',sourceCompanyLabel:'旧会社',periodLabel:'2026年9月')];
  },openOwnPdf:(entry,action) async {opened.add('${entry.id}:${action.name}');})));
  await t.pumpAndSettle();
  expect(find.text('書類一覧を確認できませんでした。'),findsOneWidget);
  expect(find.text('保管済みの本人書類はありません。'),findsNothing);
  await t.tap(find.text('再読み込み'));await t.pumpAndSettle();
  await t.tap(find.text('給与明細'));await t.pumpAndSettle();
  expect(opened,['own-receipt:preview']);
  await t.tap(find.byTooltip('閲覧・保存・印刷'));await t.pumpAndSettle();
  expect(find.text('編集'),findsNothing);expect(find.text('削除'),findsNothing);
  await t.tap(find.text('印刷'));await t.pumpAndSettle();
  expect(opened.last,'own-receipt:print');
 });
}
