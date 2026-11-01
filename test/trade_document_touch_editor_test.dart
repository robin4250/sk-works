import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/features/shared/trade_document_touch_editor_page.dart';

Map<String,dynamic> body()=>TradeDocumentTermsSnapshot.initialize({
 'version':1,'kind':'order','month':'2026-10','issue_date':'2026-10-01','order_date':'2026-10-01',
 'work_name':'登録工事','work_address':'東京都の現場','period_start':'2026-10-01','period_end':'2026-10-31',
 'total_amount_yen':110000,'tax_amount_yen':10000,'payment_conditions':'完了確認後に支払い','notes':'保存前の特記',
 'issuer':{'name':'登録自社','address':'自社の登録住所','phone':'000-111-2222'},
 'counterparty':{'name':'登録相手','address':'相手の登録住所'},
 'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'登録自社'},
});
class Scope extends ChangeNotifier {
 bool valid=true;
 void check(){if(!valid)throw StateError('scope changed');}
 void revoke(){valid=false;notifyListeners();}
 void restore(){valid=true;notifyListeners();}
}
class Harness {
 Harness(this.scope);
 final Scope scope;
 final saves=<Map<String,dynamic>>[];
 Future<void> Function(Map<String,dynamic>)? save;
 int companyEdits=0;
}
Future<Harness> mount(WidgetTester t,{Size size=const Size(600,900),Map<String,dynamic>? payload,
 bool amount=false,bool extended=false})async{
 t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
 t.view.devicePixelRatio=1;t.view.physicalSize=size;
 addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);addTearDown(t.view.resetViewInsets);
 final h=Harness(Scope());
 final initial=TradeDocumentFormDraft.fromPayload(payload??body(),allowAmountEditing:amount);
 await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
  onPressed:()=>Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>TradeDocumentTouchEditorPage(
   initial:initial,requireScope:h.scope.check,scopeChanges:h.scope,canEdit:true,allowExtendedFields:extended,
   buildPreview:(_)async=>Uint8List.fromList([1]),
   onSave:(value)async{h.saves.add(value);await h.save?.call(value);},
   onEditOwnCompany:()=>h.companyEdits++))),child:const Text('開く'))))));
 await t.tap(find.text('開く'));await t.pumpAndSettle();
 addTearDown(()async{await t.pumpWidget(const SizedBox.shrink());h.scope.dispose();});
 return h;
}
Finder target(String id)=>find.byKey(ValueKey('trade-touch-target-$id'));
Finder input(String path)=>find.byKey(ValueKey('trade-touch-input-$path'));
Finder get confirm=>find.byKey(const Key('trade-touch-field-confirm'));
InteractiveViewer viewer(WidgetTester t)=>t.widget<InteractiveViewer>(find.byKey(const Key('trade-touch-viewport')));
Future<void> pinch(WidgetTester t,Offset center)async{
 final a=await t.startGesture(center-const Offset(22,0),pointer:1);
 final b=await t.startGesture(center+const Offset(22,0),pointer:2);
 await t.pump(const Duration(milliseconds:16));
 await a.moveTo(center-const Offset(66,0));await b.moveTo(center+const Offset(66,0));
 await t.pump(const Duration(milliseconds:16));await a.up();await b.up();await t.pumpAndSettle();
}
void main(){
 for(final kind in ['order','acceptance']){
  testWidgets('$kind separates both registration headings from company names by one line',(t)async{
   final payload=body()..['kind']=kind;
   if(kind=='acceptance')payload['acceptance_text']='承諾します。';
   await mount(t,payload:payload);
   final gap=t.widget<SizedBox>(find.byKey(const Key('trade-input-issuer-heading-gap')));
   expect(gap.height,11.25);
   final heading=kind=='order'?'受注者の登録情報':'注文者の登録情報';
   expect(find.textContaining('$heading\n\n登録相手'),findsOneWidget);
  });
 }

 for (final kind in ['order','acceptance']) {
  testWidgets('$kind second page has the same complete immutable terms before front input', (t) async {
   final payload=body()..['kind']=kind..['issue_date']=''..['work_name']='';
   if(kind=='acceptance')payload['acceptance_text']='承諾します。';
   final original=payload['contract_terms'].toString();
   final h=await mount(t,payload:payload);
   await t.tap(find.byKey(const ValueKey('trade-touch-page-1')));await t.pumpAndSettle();
   expect(find.byKey(const Key('trade-touch-terms-paper')),findsOneWidget);
   final shown=t.widget<Text>(find.byKey(const Key('trade-touch-terms-text'))).data!;
   final terms=TradeDocumentTermsSnapshot.fromJson(payload['contract_terms']);
   for(final article in terms.articles){
    expect(shown,contains(article.$1));
    for(final paragraph in article.$2){expect(shown,contains(paragraph));}
   }
   expect(h.saves,isEmpty);expect(payload['contract_terms'].toString(),original);
   expect(target('work_name'),findsNothing);
   await t.tap(find.byKey(const ValueKey('trade-touch-page-0')));await t.pumpAndSettle();
   expect(target('work_name'),findsOneWidget);expect(h.saves,isEmpty);
  });
 }
 testWidgets('scope revocation removes second-page terms and cannot revive them', (t) async {
  final h=await mount(t);
  await t.tap(find.byKey(const ValueKey('trade-touch-page-1')));await t.pumpAndSettle();
  expect(find.byKey(const Key('trade-touch-terms-text')),findsOneWidget);
  h.scope.revoke();await t.pumpAndSettle();h.scope.restore();await t.pumpAndSettle();
  expect(find.byKey(const Key('trade-touch-terms-text')),findsNothing);
  expect(find.textContaining('入力を停止'),findsOneWidget);expect(h.saves,isEmpty);
 });

 testWidgets('month-end selection stays distinct from numeric 31 and saves only on explicit confirm',(t)async{
  final h=await mount(t,extended:true);
  await t.tap(target('cutoffs'));await t.pumpAndSettle();
  await t.tap(find.widgetWithText(ChoiceChip,'末日'));await t.pumpAndSettle();
  expect(h.saves,isEmpty);
  await t.tap(confirm);await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('trade-touch-save')));await t.pumpAndSettle();
  expect(h.saves.single['form_fields']['progress_cutoff_day'],'month_end');
  expect(h.saves.single['form_fields']['schema'],2);expect(t.takeException(),isNull);
 });
 testWidgets('unavailable server capability explains month-end without silently saving 31',(t)async{
  final h=await mount(t);
  await t.tap(target('cutoffs'));await t.pumpAndSettle();
  expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'末日')).onSelected,isNull);
  expect(find.textContaining('末日の設定は'),findsOneWidget);expect(h.saves,isEmpty);
 });
 testWidgets('approved paper has nine editable rows and trusted company source link',(t)async{
  final h=await mount(t);
  for(var i=0;i<9;i++){expect(target('row_$i'),findsOneWidget);}
  await t.tap(target('issuer'));await t.pumpAndSettle();
  expect(find.byType(TextField),findsNothing);expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('自社の登録住所')),findsOneWidget);
  await t.tap(find.text('会社情報の画面を開く'));await t.pumpAndSettle();
  expect(h.companyEdits,1);expect(h.saves,isEmpty);
 });
 testWidgets('long registered company remains scrollable with visible close in landscape',(t)async{
  final value=body();
  value['issuer']['name']=List.filled(500,'長').join();
  value['issuer']['address']=List.filled(500,'住').join();
  value['issuer']['representative_name']=List.filled(500,'代').join();
  await mount(t,size:const Size(932,430),payload:value);
  await t.tap(target('issuer'));await t.pumpAndSettle();
  expect(find.byType(TextField),findsNothing);expect(t.takeException(),isNull);
  final close=find.byKey(const Key('trade-touch-company-close'));
  expect(t.getBottomRight(close).dy,lessThanOrEqualTo(430));
  await t.tap(close);await t.pumpAndSettle();
  expect(find.byKey(const Key('trade-touch-viewport')),findsOneWidget);
 });
 testWidgets('two-finger zoom then paper tap opens the correct field, not a gesture-end sheet',(t)async{
  await mount(t);
  final original=viewer(t).transformationController!.value.getMaxScaleOnAxis();
  await pinch(t,t.getCenter(target('work_name')));
  expect(viewer(t).transformationController!.value.getMaxScaleOnAxis(),greaterThan(original*1.2));
  expect(confirm,findsNothing);
  await t.tap(target('work_name'));await t.pumpAndSettle();
  expect(input('base.work_name'),findsOneWidget);expect(input('base.work_address'),findsNothing);
 });
 testWidgets('acceptance prose tap cannot hit the registered company header',(t)async{
  final value=body()..['kind']='acceptance'..['acceptance_text']='ご注文をお請けします。';
  await mount(t,payload:value);
  await t.tap(target('intro'));await t.pumpAndSettle();
  expect(input('base.acceptance_text'),findsOneWidget);
  expect(find.byKey(const Key('trade-touch-company-close')),findsNothing);
 });
 testWidgets('pan does not open input',(t)async{
  await mount(t);
  final x=viewer(t).transformationController!.value.storage[12];
  await t.dragFrom(t.getCenter(find.byKey(const Key('trade-touch-viewport'))),const Offset(-100,-40));
  await t.pumpAndSettle();expect(confirm,findsNothing);
  expect(viewer(t).transformationController!.value.storage[12],isNot(x));
 });
 testWidgets('small keyboard confirmation hides keyboard, returns to fit, and allows next field',(t)async{
  final h=await mount(t,size:const Size(320,568));
  final fit=viewer(t).transformationController!.value.getMaxScaleOnAxis();
  await pinch(t,t.getCenter(target('work_name')));
  await t.tap(target('work_name'));await t.pumpAndSettle();
  const value='日本語の長い工事名称をここで入力して確認します';
  await t.enterText(input('base.work_name'),value);
  t.view.viewInsets=const FakeViewPadding(bottom:280);await t.pumpAndSettle();
  expect(t.getBottomRight(confirm).dy,lessThanOrEqualTo(289));
  await t.tap(confirm);await t.pumpAndSettle();
  expect(t.testTextInput.isVisible,false);expect(find.byType(TextField),findsNothing);
  t.view.viewInsets=const FakeViewPadding();await t.pumpAndSettle();
  expect(viewer(t).transformationController!.value.getMaxScaleOnAxis(),closeTo(fit,.001));
  expect(find.text(value),findsOneWidget);expect(h.saves,isEmpty);
  await t.tap(target('work_address'));await t.pumpAndSettle();
  expect(input('base.work_address'),findsOneWidget);
 });
 testWidgets('cancel discards only unconfirmed input',(t)async{
  await mount(t);await t.tap(target('work_name'));await t.pumpAndSettle();
  await t.enterText(input('base.work_name'),'取消予定の工事');
  await t.tap(find.text('戻る'));await t.pumpAndSettle();
  expect(find.text('登録工事'),findsOneWidget);expect(find.text('取消予定の工事'),findsNothing);
 });
 testWidgets('invalid long Japanese stays in sheet with explanation',(t)async{
  await mount(t);await t.tap(target('work_name'));await t.pumpAndSettle();
  final text=List.filled(241,'工').join();await t.enterText(input('base.work_name'),text);
  await t.tap(confirm);await t.pumpAndSettle();
  expect(confirm,findsOneWidget);expect(find.byKey(const Key('trade-touch-field-error')),findsOneWidget);
  expect(t.widget<TextField>(input('base.work_name')).controller!.text,text);
 });
 testWidgets('row sheet commits a complete row without calculating totals or missing amounts',(t)async{
  final h=await mount(t);await t.tap(target('row_0'));await t.pumpAndSettle();
  await t.enterText(input('form.rows.0.item'),'日本語の施工明細');
  await t.enterText(input('form.rows.0.quantity'),'2.5');
  await t.ensureVisible(input('form.rows.0.unit_price_yen'));await t.enterText(input('form.rows.0.unit_price_yen'),'1000');
  await t.tap(confirm);await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('trade-touch-save')));await t.pumpAndSettle();
  final saved=h.saves.single;expect(saved['form_fields']['rows'][0]['item'],'日本語の施工明細');
  expect(saved['form_fields']['rows'][0]['quantity'],'2.5');expect(saved['form_fields']['rows'][0]['unit_price_yen'],1000);
  expect(saved['form_fields']['rows'][0]['amount_yen'],isNull);expect(saved['total_amount_yen'],110000);expect(saved['tax_amount_yen'],10000);
 });
 testWidgets('invalid row decimal is not closed or silently rounded',(t)async{
  await mount(t);await t.tap(target('row_0'));await t.pumpAndSettle();
  await t.enterText(input('form.rows.0.quantity'),'1.1234');await t.tap(confirm);await t.pumpAndSettle();
  expect(confirm,findsOneWidget);expect(find.byKey(const Key('trade-touch-field-error')),findsOneWidget);
  expect(t.widget<TextField>(input('form.rows.0.quantity')).controller!.text,'1.1234');
 });
 testWidgets('calendar selection commits date and choice selects explicit no',(t)async{
  final h=await mount(t);await t.tap(target('issue_date'));await t.pumpAndSettle();
  await t.tap(find.text('日付'));await t.pumpAndSettle();
  await t.tap(find.text('15').last);await t.tap(find.text('決定'));await t.pumpAndSettle();
  await t.tap(confirm);await t.pumpAndSettle();
  await t.tap(target('payment_advance'));await t.pumpAndSettle();
  await t.tap(find.widgetWithText(ChoiceChip,'無'));await t.tap(confirm);await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('trade-touch-save')));await t.pumpAndSettle();
  expect(h.saves.single['issue_date'],'2026-10-15');
  expect(h.saves.single['form_fields']['payments']['advance'],{'choice':'no','date':null,'amount_yen':null});
 });
 testWidgets('monthly amount is read-only and required fields prevent persistence',(t)async{
  final value=body()..['work_name']='';final h=await mount(t,payload:value);
  await t.tap(target('amount'));await t.pumpAndSettle();expect(find.byType(TextField),findsNothing);
  await t.tap(find.byKey(const Key('trade-touch-save')));await t.pumpAndSettle();
  expect(h.saves,isEmpty);expect(find.byKey(const Key('trade-touch-error')),findsOneWidget);
 });
 testWidgets('scope revocation destroys the active sheet and never revives it',(t)async{
  final h=await mount(t);await t.tap(target('work_name'));await t.pumpAndSettle();
  await t.enterText(input('base.work_name'),'消去する未確定入力');h.scope.revoke();await t.pumpAndSettle();
  expect(find.byType(TextField),findsNothing);expect(find.textContaining('登録自社'),findsNothing);
  h.scope.restore();await t.pumpAndSettle();
  expect(find.byKey(const Key('trade-touch-viewport')),findsNothing);expect(h.saves,isEmpty);
 });
 testWidgets('background closes input and late save completion cannot navigate as success',(t)async{
  final h=await mount(t);final gate=Completer<void>();h.save=(_)=>gate.future;
  await t.tap(find.byKey(const Key('trade-touch-save')));await t.pump();
  final state=t.state(find.byType(TradeDocumentTouchEditorPage)) as WidgetsBindingObserver;
  state.didChangeAppLifecycleState(AppLifecycleState.paused);await t.pumpAndSettle();
  gate.complete();await t.pumpAndSettle();
  expect(find.text('入力を停止しました。元の画面から開き直してください。'),findsOneWidget);
  expect(find.text('開く'),findsNothing);expect(h.saves,hasLength(1));
 });
 testWidgets('unknown persistence result keeps draft and blocks duplicate save',(t)async{
  final h=await mount(t);h.save=(_)async=>throw StateError('fixture unknown');
  await t.tap(find.byKey(const Key('trade-touch-save')));await t.pumpAndSettle();
  expect(h.saves,hasLength(1));expect(t.widget<FilledButton>(find.byKey(const Key('trade-touch-save'))).onPressed,isNull);
  expect(find.text('登録工事'),findsOneWidget);expect(find.textContaining('保存結果を確認できません'),findsOneWidget);
 });
}
