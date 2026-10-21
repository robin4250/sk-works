import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/people/company_representative_card.dart';
import 'company_representative_repository_test.dart' show Fixture;
void main() {
  testWidgets('explicit company -> save -> reload and folded help', (tester) async {
    final f=Fixture();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
      child:CompanyRepresentativeCard(repository:f.repo)))));
    await tester.pumpAndSettle();
    expect(find.text('代表者名を保存'),findsNothing);
    await tester.tap(find.byTooltip('代表者名のヘルプ'));await tester.pumpAndSettle();
    expect(find.text('発注者の代表者名'),findsOneWidget);
    await tester.tap(find.text('閉じる'));await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));await tester.pumpAndSettle();
    await tester.tap(find.text('甲会社').last);await tester.pumpAndSettle();
    expect(find.text('保存先：甲会社'),findsOneWidget);
    await tester.enterText(find.byType(TextField),'新代表');
    await tester.tap(find.text('代表者名を保存'));await tester.pumpAndSettle();
    expect(find.text('選択した会社の代表者名を保存しました。'),findsOneWidget);
    await tester.tap(find.text('設定を再読込'));await tester.pumpAndSettle();
    expect(find.text('新代表'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(f.close);
  }, timeout: const Timeout(Duration(seconds: 30)));
  testWidgets('auth change removes old company and representative text', (tester) async {
    final f=Fixture();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:CompanyRepresentativeCard(repository:f.repo))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));await tester.pumpAndSettle();
    await tester.tap(find.text('甲会社').last);await tester.pumpAndSettle();
    f.currentToken='new-token';f.changes.add((actor:'00000000-0000-0000-0000-000000000001',token:f.currentToken));
    await tester.pumpAndSettle();
    expect(find.text('甲代表'),findsNothing);expect(find.text('保存先：甲会社'),findsNothing);
    expect(find.text('会社データを開き直してください。'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(f.close);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
