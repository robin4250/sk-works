import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/companies/trade_company_page.dart';
import 'package:sk_works/features/companies/trade_company_repository.dart';
import 'package:sk_works/features/shared/standalone_trade_document_page.dart';
class _Directory implements TradeCompanyRepository {
 @override Future<List<TradeCompanyRecord>> loadAll()async=>[TradeCompanyRecord.fromJson({'id':'10000000-0000-4000-8000-000000000001','name':'登録会社','trade_role':'both'})];
 @override Future<Map<String,dynamic>> linkWorkspace()async=>{'enabled':false};
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
void main(){
 for(final mode in TradeCompanyPageMode.values){
  testWidgets('actual $mode generation action selects its correct document and selected directory ID',(tester)async{
   tester.view.physicalSize=const Size(1200,1600);tester.view.devicePixelRatio=1;addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
   await tester.pumpWidget(MaterialApp(home:TradeCompanyPage(mode:mode,repository:_Directory())));await tester.pumpAndSettle();
   await tester.tap(find.text('登録会社').first);await tester.pumpAndSettle();
   await tester.tap(find.text(mode==TradeCompanyPageMode.customer?'注文請書生成':'注文書生成'));await tester.pumpAndSettle();
   final page=tester.widget<StandaloneTradeDocumentPage>(find.byType(StandaloneTradeDocumentPage));expect(page.acceptance,mode==TradeCompanyPageMode.customer);expect(page.tradeCompanyId,'10000000-0000-4000-8000-000000000001');
   await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
 }
}
