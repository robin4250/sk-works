import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/standalone_trade_document_operation_gate.dart';
import 'package:sk_works/features/shared/trade_documents_hub_contract.dart';
import 'package:sk_works/features/shared/trade_documents_hub_page.dart';
import 'package:sk_works/features/shared/trade_documents_hub_repository.dart';

class _Repository extends ChangeNotifier implements TradeDocumentsHubRepository {
 _Repository(this.role,{this.enabled=true});
 final String role;bool enabled;bool closed=false;int refreshes=0;
 Completer<void>? pendingRefresh;
 @override TradeDocumentsHubSnapshot get snapshot=>TradeDocumentsHubSnapshot(companyId:'self',role:role,
  availability:TradeDocumentsHubAvailability(supported:true,enabled:enabled),parties:const [
   TradeDocumentsHubParty(id:'supplier',name:'協力会社A',role:'subcontractor'),
   TradeDocumentsHubParty(id:'customer',name:'取引会社B',role:'customer')]);
 @override Future<TradeDocumentsHubSnapshot> load()async{requireCurrent();return snapshot;}
 @override void requireCurrent(){if(closed){throw StateError('retired');}}
 @override void requireOperation(String company,String party,bool acceptance){
  requireCurrent();
  if(!enabled||company!='self'||(acceptance?party!='customer':party!='supplier')){throw StateError('unavailable');}
 }
 @override Future<void> refreshOperation(String c,String p,bool a)async{
  refreshes++;requireOperation(c,p,a);await pendingRefresh?.future;requireOperation(c,p,a);
 }
 void off(){enabled=false;notifyListeners();}
 @override void dispose(){if(closed){return;}closed=true;super.dispose();}
 @override dynamic noSuchMethod(Invocation i)=>super.noSuchMethod(i);
}
class _Clock extends Fake implements Stopwatch {
 Duration value=Duration.zero;bool running=false;
 @override Duration get elapsed=>value;
 @override bool get isRunning=>running;
 @override void reset(){value=Duration.zero;}
 @override void start(){running=true;}
 @override void stop(){running=false;}
}
void main(){
 test('an observed monotonic expiry retires permanently and never revives from a later refresh',()async{
  final repository=_Repository('manager'),clock=_Clock();
  final lease=TradeDocumentsOperationLease(repository:repository,companyId:'self',
   tradeCompanyId:'supplier',acceptance:false,stopwatch:clock);
  try{
   await lease.refresh();lease.requireCurrent();clock.value=const Duration(seconds:15);
   expect(lease.requireCurrent,throwsStateError);clock.value=Duration.zero;
   await expectLater(lease.refresh(),throwsStateError);expect(repository.refreshes,1);
  }finally{lease.dispose();repository.dispose();}
 });
 test('a refresh completing after the monotonic deadline cannot revive the prior lease',()async{
  final repository=_Repository('manager'),clock=_Clock();
  final lease=TradeDocumentsOperationLease(repository:repository,companyId:'self',
   tradeCompanyId:'supplier',acceptance:false,stopwatch:clock);
  try{
   await lease.refresh();clock.value=const Duration(seconds:14);
   repository.pendingRefresh=Completer<void>();final pending=lease.refresh();
   clock.value=const Duration(seconds:16);repository.pendingRefresh!.complete();
   await expectLater(pending,throwsStateError);expect(lease.requireCurrent,throwsStateError);
  }finally{lease.dispose();repository.dispose();}
 });
 for(final role in ['owner','admin','manager']){
  testWidgets('$role uses the same two generation actions and exact selected target',(t)async{
   final repository=_Repository(role);StandaloneTradeDocumentOperationGate? captured;
   await t.pumpWidget(MaterialApp(home:TradeDocumentsHubPage(repositoryOverride:repository,
    generatorBuilder:(party,acceptance,gate){captured=gate;return Scaffold(
     body:Column(children:[Text('${party.id}:$acceptance'),TextButton(
      onPressed:()=>Navigator.pop(t.element(find.byType(Scaffold).last)),child:const Text('閉じる'))]));})));
   await t.pumpAndSettle();
   expect(find.text('注文書生成'),findsOneWidget);expect(find.text('請書生成'),findsOneWidget);
   await t.tap(find.byKey(const Key('trade-hub-order')));await t.pumpAndSettle();
   expect(find.text('協力会社A'),findsOneWidget);expect(find.text('取引会社B'),findsNothing);
   await t.tap(find.text('協力会社A'));await t.pumpAndSettle();
   expect(find.text('supplier:false'),findsOneWidget);expect(captured!.companyId,'self');
   expect(captured!.tradeCompanyId,'supplier');expect(captured!.acceptance,false);
   captured!.requireCurrent();expect(repository.refreshes,greaterThan(0));
   repository.off();await t.pump();expect(captured!.requireCurrent,throwsStateError);
   await t.tap(find.text('閉じる'));await t.pumpAndSettle();
   expect(t.widget<FilledButton>(find.byKey(const Key('trade-hub-order'))).onPressed,isNull);
   expect(t.widget<FilledButton>(find.byKey(const Key('trade-hub-acceptance'))).onPressed,isNull);
   await t.pumpWidget(const SizedBox.shrink());expect(repository.closed,true);
  });
 }
 testWidgets('OFF keeps the entry visible while both new generation actions are disabled',(t)async{
  final repository=_Repository('manager',enabled:false);
  await t.pumpWidget(MaterialApp(home:TradeDocumentsHubPage(repositoryOverride:repository)));
  await t.pumpAndSettle();
  expect(find.text('マスター設定：OFF'),findsOneWidget);
  expect(t.widget<FilledButton>(find.byKey(const Key('trade-hub-order'))).onPressed,isNull);
  expect(t.widget<FilledButton>(find.byKey(const Key('trade-hub-acceptance'))).onPressed,isNull);
  expect(repository.refreshes,0);await t.pumpWidget(const SizedBox.shrink());
 });
}
