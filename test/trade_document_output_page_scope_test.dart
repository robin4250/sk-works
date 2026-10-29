import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
// Pinned printing 5.15.1 platform API: the fake exercises the real widget's
// native-print boundary and retained onLayout callback, without opening a printer.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/features/shared/trade_document_output_layout.dart';
import 'package:sk_works/features/shared/trade_document_output_page.dart';
import 'package:sk_works/features/shared/trade_document_output_selector.dart';

class _LifecycleBinding extends AutomatedTestWidgetsFlutterBinding {
  bool unknown=false;
  @override AppLifecycleState? get lifecycleState=>unknown?null:super.lifecycleState;
}
class _Printing extends PrintingPlatform {
  LayoutCallback? layout;
  final completed=Completer<bool>();
  int prints=0;
  @override Future<PrintingInfo> info()async=>const PrintingInfo(canPrint:true,canShare:true,canRaster:false);
  @override Future<bool> layoutPdf(Printer? printer,LayoutCallback onLayout,String name,PdfPageFormat format,
    bool dynamicLayout,bool usePrinterSettings,OutputType outputType,bool forceCustomPrintPaper,bool windowsModernDialog)async{
    prints++;layout=onLayout;return completed.future;
  }
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
Map<String,dynamic> _payload({bool known=false}){
  final value=<String,dynamic>{'version':1,'kind':'acceptance','month':'2026-10','issue_date':'2026-09-30','order_date':'2026-09-30',
    'work_name':'Synthetic work','work_address':'Synthetic place','acceptance_text':'Synthetic acceptance','issuer':{'name':'Synthetic issuer'},
    'counterparty':{'name':'Synthetic partner'},'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'Synthetic issuer'}};
  return known?TradeDocumentTermsSnapshot.initialize(value):value;
}
Future<Uint8List> _pdf(WidgetTester tester)async{
  final document=pw.Document();
  for(var page=0;page<2;page++){document.addPage(pw.Page(build:(_)=>pw.Container(width:10+page.toDouble(),height:10)));}
  return (await tester.runAsync(()=>document.save().timeout(const Duration(seconds:5))))!;
}
Future<void> _mount(WidgetTester tester,Uint8List bytes,{required VoidCallback verify,bool known=false,Listenable? changes})async{
  await tester.pumpWidget(MaterialApp(home:TradeDocumentOutputPage(payload:_payload(known:known),canonicalBytes:bytes,requireScope:verify,scopeChanges:changes)));
  await tester.pumpAndSettle();
}
void main(){
  final binding=_LifecycleBinding();late PrintingPlatform original;late _Printing printing;
  setUp((){binding.unknown=false;binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);original=PrintingPlatform.instance;printing=_Printing();PrintingPlatform.instance=printing;});
  tearDown((){binding.unknown=false;binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);if(!printing.completed.isCompleted)printing.completed.complete(false);PrintingPlatform.instance=original;});
  testWidgets('unknown lifecycle on entry refuses a PDF and never revives after resume',(tester)async{
    final bytes=await _pdf(tester);binding.unknown=true;
    await _mount(tester,bytes,verify:(){});
    expect(find.byType(TradeDocumentOutputPage),findsOneWidget);expect(find.byType(PdfPreview),findsNothing);
    binding.unknown=false;binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    expect(find.byType(PdfPreview),findsNothing);expect(printing.prints,0);expect(tester.takeException(),isNull);
  });
  testWidgets('legacy original bytes are preserved and no format upgrade selector appears',(tester)async{
    final bytes=await _pdf(tester),originalBytes=Uint8List.fromList(bytes);
    await _mount(tester,bytes,verify:(){});
    expect(find.byType(TradeDocumentOutputSelector),findsNothing);
    final callback=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
    expect(await callback(PdfPageFormat.a4),originalBytes);expect(bytes,originalBytes);expect(printing.prints,0);expect(tester.takeException(),isNull);
  });
  for(final state in [AppLifecycleState.inactive,AppLifecycleState.paused,AppLifecycleState.hidden]){
    testWidgets('without owned print $state retires PDF permanently',(tester)async{
      final bytes=await _pdf(tester);await _mount(tester,bytes,verify:(){});
      final callback=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
      binding.handleAppLifecycleStateChanged(state);binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
      expect(find.byType(PdfPreview),findsNothing);await expectLater(callback(PdfPageFormat.a4),throwsStateError);
      expect(printing.prints,0);expect(tester.takeException(),isNull);
    });
  }
  testWidgets('scope changes immediately mask PDF and retained preview callback cannot return old bytes',(tester)async{
    final changes=ValueNotifier(0);var allowed=true;final bytes=await _pdf(tester);
    await _mount(tester,bytes,verify:(){if(!allowed)throw StateError('scope retired');},changes:changes);
    final callback=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
    allowed=false;changes.value++;await tester.pumpAndSettle();
    expect(find.byType(PdfPreview),findsNothing);await expectLater(callback(PdfPageFormat.a4),throwsStateError);
    await tester.pumpWidget(const SizedBox.shrink());changes.dispose();expect(tester.takeException(),isNull);
  });
  for(final afterAwait in [false,true]){
    testWidgets('format renderer scope rejection before/after await=$afterAwait retires existing PDF',(tester)async{
      var allowed=true,checks=0;final bytes=await _pdf(tester);
      await _mount(tester,bytes,known:true,verify:(){checks++;if(!allowed)throw StateError('scope retired');});
      final selector=tester.widget<TradeDocumentOutputSelector>(find.byType(TradeDocumentOutputSelector));
      final before=checks;
      if(!afterAwait)allowed=false;
      selector.onChanged(TradeDocumentOutputLayout.a4TwoPages);
      if(afterAwait){expect(checks,greaterThan(before));allowed=false;}
      await tester.pumpAndSettle();
      expect(checks,greaterThan(before));expect(find.byType(PdfPreview),findsNothing);
      expect(printing.prints,0);expect(tester.takeException(),isNull);
    });
  }
  testWidgets('owned native print allows inactive exact bytes until print ends then retires',(tester)async{
    final bytes=await _pdf(tester),snapshot=Uint8List.fromList(bytes);await _mount(tester,bytes,verify:(){});
    await tester.tap(find.widgetWithText(OutlinedButton,'印刷'));await tester.pump();expect(printing.prints,1);expect(printing.layout,isNotNull);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(await printing.layout!(PdfPageFormat.a4),snapshot);expect(bytes,snapshot);
    printing.completed.complete(false);await tester.pump();binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    expect(find.byType(PdfPreview),findsNothing);await expectLater(printing.layout!(PdfPageFormat.a4),throwsStateError);expect(tester.takeException(),isNull);
  });
  testWidgets('owned print never exempts scope invalidation and retained native onLayout refuses',(tester)async{
    final changes=ValueNotifier(0);var allowed=true;final bytes=await _pdf(tester);
    await _mount(tester,bytes,verify:(){if(!allowed)throw StateError('scope retired');},changes:changes);
    await tester.tap(find.widgetWithText(OutlinedButton,'印刷'));await tester.pump();binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(await printing.layout!(PdfPageFormat.a4),bytes);
    allowed=false;changes.value++;await expectLater(printing.layout!(PdfPageFormat.a4),throwsStateError);
    printing.completed.complete(false);binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
    expect(find.byType(PdfPreview),findsNothing);expect(printing.prints,1);expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());changes.dispose();
  });
  testWidgets('background during owned print rejects late layout and cannot revive on resume',(tester)async{
    final bytes=await _pdf(tester);await _mount(tester,bytes,verify:(){});
    await tester.tap(find.widgetWithText(OutlinedButton,'印刷'));await tester.pump();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await expectLater(printing.layout!(PdfPageFormat.a4),throwsStateError);
    printing.completed.complete(false);await tester.pumpAndSettle();expect(find.byType(PdfPreview),findsNothing);expect(tester.takeException(),isNull);
  });
}
