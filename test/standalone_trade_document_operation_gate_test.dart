import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// The pinned printing platform is exercised without opening a real printer.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/features/shared/standalone_trade_document_operation_gate.dart';
import 'package:sk_works/features/shared/standalone_trade_document_page.dart';
import 'package:sk_works/features/shared/standalone_trade_document_repository.dart';
import 'package:sk_works/features/shared/trade_document_form_session.dart';
import 'package:sk_works/features/shared/trade_document_touch_editor_page.dart';
import 'package:sk_works/features/shared/trade_document_output_selector.dart';
import 'package:sk_works/features/shared/trade_document_output_layout.dart';

const _actor='10000000-0000-4000-8000-000000000001';
const _company='10000000-0000-4000-8000-000000000002';
const _trade='20000000-0000-4000-8000-000000000001';
String _token(){String part(Object v)=>base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=','');
 return '${part({'alg':'HS256','typ':'JWT'})}.${part({'sub':_actor,'session_id':'30000000-0000-4000-8000-000000000001','role':'authenticated','exp':DateTime.now().millisecondsSinceEpoch~/1000+3600})}.synthetic';}
class _Gate extends ChangeNotifier implements StandaloneTradeDocumentOperationGate {
 _Gate({this.companyId=_company,this.tradeCompanyId=_trade,this.acceptance=false,this.allowed=true});
 @override final String companyId,tradeCompanyId;
 @override final bool acceptance;
 bool allowed;int refreshes=0;Completer<void>? hold;
 @override void requireCurrent(){if(!allowed)throw StateError('Synthetic master unavailable');}
 @override Future<void> refresh()async{refreshes++;requireCurrent();await hold?.future;}
 void revoke(){allowed=false;notifyListeners();}
}
class _Repo extends StandaloneTradeDocumentRepository {
 _Repo(super.client,TradeDocumentFormSession scope,{super.managedCompanyId}):super(session:scope);
 int loads=0;Completer<void>? hold;
 @override Future<Map<String,dynamic>> load({required String tradeCompanyId,required bool acceptance})async{
  loads++;verify();await hold?.future;
  return {'company_id':_company,'trade_company_id':_trade,'acceptance':acceptance,
   'issuer':{'name':'Synthetic issuer','address':'Synthetic address','representative_name':'Synthetic representative'},
   'counterparty':{'name':'Synthetic recipient','address':'Synthetic recipient address','representative_name':'Synthetic recipient representative'},
   'template':{'work_name':'Synthetic work','work_address':'Synthetic place'},'company_seal_enabled':false,
   'company_seal_snapshot':{'version':1,'style':'legacy','name':'Synthetic issuer'}};
 }
}
class _Printer extends PrintingPlatform {
 int prints=0;LayoutCallback? callback;Completer<bool>? end;
 @override Future<PrintingInfo> info()async=>const PrintingInfo(canPrint:true,canShare:true,canRaster:false);
 @override Future<bool> layoutPdf(Printer? printer,LayoutCallback onLayout,String name,PdfPageFormat format,
  bool dynamicLayout,bool usePrinterSettings,OutputType outputType,bool forceCustomPrintPaper,bool windowsModernDialog)async{
  prints++;callback=onLayout;end=Completer<bool>();return end!.future;
 }
 @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class _Fixture {
 late final client=SupabaseClient('https://synthetic.invalid','synthetic-public',authOptions:const AuthClientOptions(autoRefreshToken:false),
  httpClient:MockClient((r)async=>http.Response(jsonEncode({'access_token':_token(),'refresh_token':'synthetic-refresh','expires_in':3600,'token_type':'bearer',
   'user':{'id':_actor,'aud':'authenticated','role':'authenticated','created_at':'2026-01-01T00:00:00Z'}}),200,headers:{'content-type':'application/json'})));
 TradeDocumentFormSession? scope;_Repo? repo;
 Future<void> mount(WidgetTester t,{_Gate? gate})async{
  t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await t.runAsync(()=>client.auth.signInWithPassword(email:'synthetic@example.invalid',password:'synthetic-password'));
  scope=TradeDocumentFormSession(client);repo=_Repo(client,scope!,managedCompanyId:gate?.companyId);
  await t.pumpWidget(MaterialApp(home:StandaloneTradeDocumentPage(tradeCompanyId:_trade,acceptance:false,
   clientOverride:client,sessionOverride:scope,repositoryOverride:repo,operationGate:gate)));
  await t.pumpAndSettle();
 }
 Future<void> close(WidgetTester t)async{await t.pumpWidget(const SizedBox.shrink());scope?.dispose();await t.runAsync(client.dispose);}
 Future<TradeDocumentTouchEditorPage> edit(WidgetTester t)async{
  await t.tap(find.widgetWithText(FilledButton,'注文書の入力・設定'));await t.pumpAndSettle();
  return t.widget<TradeDocumentTouchEditorPage>(find.byType(TradeDocumentTouchEditorPage));
 }
 Map<String,dynamic> valid(TradeDocumentTouchEditorPage editor)=>editor.initial.withChanges({'issue_date':'2026-10-30','order_date':'2026-10-30',
  'period_start':'2026-10-01','period_end':'2026-10-31','total_amount_yen':110000,'tax_amount_yen':10000}).payload;
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();late PrintingPlatform original;late _Printer printer;
 setUp((){original=PrintingPlatform.instance;printer=_Printer();PrintingPlatform.instance=printer;});
 tearDown((){if(printer.end?.isCompleted==false)printer.end!.complete(false);PrintingPlatform.instance=original;});
 testWidgets('A4 and A3 PDF format can be selected before generating a new registration document',(t)async{
  final f=_Fixture();try{
   await f.mount(t);
   expect(find.byType(PdfPreview),findsNothing);
   final field=find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>);
   await t.ensureVisible(field);await t.tap(field);await t.pumpAndSettle();
   await t.tap(find.text('A3横・見開き1枚（2ページを左右に配置）').last);await t.pumpAndSettle();
   expect(t.widget<TradeDocumentOutputSelector>(find.byType(TradeDocumentOutputSelector)).value,TradeDocumentOutputLayout.a3Landscape);
   expect(find.byType(PdfPreview),findsNothing);expect(printer.prints,0);
   expect(t.takeException(),isNull);
  }finally{await f.close(t);}
 });
 testWidgets('absent optional gate retains existing registration-only path',(t)async{
  final f=_Fixture();try{await f.mount(t);expect(f.repo!.loads,1);expect(find.text('注文書の入力・設定'),findsOneWidget);expect(printer.prints,0);}
  finally{await f.close(t);}
 });
 testWidgets('master unavailable refuses before any registered-company read',(t)async{
  final f=_Fixture(),g=_Gate(allowed:false);try{await f.mount(t,gate:g);expect(f.repo!.loads,0);expect(find.text('注文書の入力・設定'),findsNothing);expect(printer.prints,0);expect(t.takeException(),isNull);}
  finally{await f.close(t);g.dispose();}
 });
 for(final bad in ['company','trade','kind']){
  testWidgets('gate $bad mismatch never exposes an editable document',(t)async{
   final f=_Fixture(),g=_Gate(companyId:bad=='company'?'foreign':_company,tradeCompanyId:bad=='trade'?'foreign':_trade,acceptance:bad=='kind');
   try{await f.mount(t,gate:g);expect(find.text('注文書の入力・設定'),findsNothing);expect(find.byType(PdfPreview),findsNothing);expect(printer.prints,0);expect(t.takeException(),isNull);}
   finally{await f.close(t);g.dispose();}
  });
 }
 testWidgets('revocation masks the live editor and rejects retained preview and save callbacks',(t)async{
  final f=_Fixture(),g=_Gate();try{await f.mount(t,gate:g);final editor=await f.edit(t),p=f.valid(editor);
   g.revoke();await t.pumpAndSettle();
   await expectLater(editor.onSave(p),throwsStateError);await expectLater(editor.buildPreview(p),throwsStateError);
   expect(find.byKey(const Key('trade-touch-save')),findsNothing);expect(printer.prints,0);expect(t.takeException(),isNull);
  }finally{await f.close(t);g.dispose();}
 });
 testWidgets('master change during awaited refresh rejects late edit confirmation',(t)async{
  final f=_Fixture(),g=_Gate();try{await f.mount(t,gate:g);final editor=await f.edit(t),p=f.valid(editor);
   g.hold=Completer<void>();final pending=editor.onSave(p);await t.pump();g.allowed=false;g.hold!.complete();
   await expectLater(pending,throwsStateError);await t.pumpAndSettle();expect(find.byKey(const Key('trade-touch-save')),findsNothing);expect(printer.prints,0);expect(t.takeException(),isNull);
  }finally{await f.close(t);g.dispose();}
 });
 testWidgets('native print callback rechecks the gate and cannot return bytes after master OFF',(t)async{
  final f=_Fixture(),g=_Gate();try{await f.mount(t,gate:g);final editor=await f.edit(t);
   await editor.onSave(f.valid(editor));Navigator.of(t.element(find.byType(TradeDocumentTouchEditorPage))).pop();await t.pumpAndSettle();
   final generate=t.widget<FilledButton>(find.widgetWithText(FilledButton,'帳票を確認')).onPressed;
   await t.runAsync(()async{await (generate as dynamic)();});await t.pumpAndSettle();
   expect(find.byType(PdfPreview),findsOneWidget);
   final preview=t.widget<PdfPreview>(find.byType(PdfPreview)).build;
   final button=find.widgetWithText(OutlinedButton,'印刷');await t.ensureVisible(button);await t.tap(button);await t.pump();await t.pump(const Duration(milliseconds:100));
   expect(printer.prints,1);final callback=printer.callback!;expect(await callback(PdfPageFormat.a4),isNotEmpty);
   g.revoke();await t.pumpAndSettle();await expectLater(callback(PdfPageFormat.a4),throwsStateError);await expectLater(preview(PdfPageFormat.a4),throwsStateError);
   printer.end!.complete(false);await t.pumpAndSettle();expect(find.byType(PdfPreview),findsNothing);expect(t.takeException(),isNull);
  }finally{await f.close(t);g.dispose();}
 });
}
