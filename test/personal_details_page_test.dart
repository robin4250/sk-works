import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/profile/personal_details_page.dart';
import 'package:sk_works/features/profile/personal_details_repository.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';
class Gateway extends ChangeNotifier implements PersonalDetailsGateway {
 @override String get actorId=>'10000000-0000-4000-8000-000000000001';
 @override bool isCurrent=true;
 @override bool pendingUnknown=false;
 int writes=0;Map<String,dynamic>? changes;bool failLoad=false;
 @override Future<PersonalDetailsSummary> load()async{if(failLoad)throw StateError('synthetic unavailable');return const PersonalDetailsSummary(revision:0,exists:false,bankRegistered:false);}
 @override Future<OwnBankAccountInput?> readBank(int r,PersonalProof p)async=>null;
 @override Future<bool> save(int r,Map<String,dynamic> c,String o,PersonalProof p)async{writes++;changes=c;return true;}
 @override Future<bool> reconcile()async=>false;
 @override Future<void> close()async{}
 void retire(){isCurrent=false;notifyListeners();}
}
void main(){
 testWidgets('failed reload invalidates previous absence and removes editable personal fields',(t)async{
  final gateway=Gateway();await t.pumpWidget(MaterialApp(home:PersonalDetailsPage(gateway:gateway)));await t.pumpAndSettle();
  expect(find.text('この個人プロフィールに口座は登録されていません。'),findsOneWidget);
  await t.enterText(find.byKey(const Key('personal-birth-date')),'1990-01-02');
  gateway.failLoad=true;await t.tap(find.text('再読み込み'));await t.pumpAndSettle();
  expect(find.text('この個人プロフィールに口座は登録されていません。'),findsNothing);
  expect(find.byKey(const Key('personal-birth-date')),findsNothing);
  expect(find.text('変更内容を確認して保存'),findsNothing);expect(gateway.writes,0);
 });
 testWidgets('only explicit confirmation saves dirty own birthday; no bank or family import',(t)async{
  t.view.physicalSize=const Size(900,1800);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final gateway=Gateway();await t.pumpWidget(MaterialApp(home:PersonalDetailsPage(gateway:gateway)));await t.pumpAndSettle();
  expect(find.text('この個人プロフィールに口座は登録されていません。'),findsOneWidget);
  await t.enterText(find.byKey(const Key('personal-birth-date')),'1990-01-02');await t.pump();
  await t.ensureVisible(find.text('変更内容を確認して保存'));await t.tap(find.text('変更内容を確認して保存'));await t.pumpAndSettle();
  expect(gateway.writes,0);await t.tap(find.text('戻る'));await t.pumpAndSettle();expect(gateway.writes,0);
  await t.tap(find.text('変更内容を確認して保存'));await t.pumpAndSettle();await t.tap(find.text('確認して保存'));await t.pumpAndSettle();
  expect(gateway.writes,1);expect(gateway.changes,{'birth_date':'1990-01-02'});
 });
 testWidgets('unknown pending disables new save and offers metadata reconciliation',(t)async{
  t.view.physicalSize=const Size(900,1800);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final gateway=Gateway()..pendingUnknown=true;await t.pumpWidget(MaterialApp(home:PersonalDetailsPage(gateway:gateway)));await t.pumpAndSettle();
  expect(find.text('保存結果を確認'),findsOneWidget);
  expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'変更内容を確認して保存')).onPressed,isNull);
  expect(gateway.writes,0);
 });
 testWidgets('session retirement clears personal fields and disables submission',(t)async{
  t.view.physicalSize=const Size(900,1800);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final gateway=Gateway();await t.pumpWidget(MaterialApp(home:PersonalDetailsPage(gateway:gateway)));await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('personal-birth-date')),'1990-01-02');gateway.retire();await t.pumpAndSettle();
  expect(find.byKey(const Key('personal-birth-date')),findsNothing);expect(gateway.writes,0);
  expect(find.text('ログイン状態が変わりました。画面を開き直してください。'),findsOneWidget);
 });
}
