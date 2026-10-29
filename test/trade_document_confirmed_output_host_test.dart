import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
// The exact pinned 5.15.1 public platform method signatures are used here.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_dialog.dart';
import 'package:sk_works/features/shared/trade_document_output_page.dart';
import 'trade_document_confirmed_output_session_test.dart' show ConfirmedOutputFixture,confirmedOutputScope;

class _NativePrinting extends PrintingPlatform{
  LayoutCallback? callback;Completer<bool>? _done;
  Completer<bool> get done=>_done??=Completer<bool>();
  int calls=0;
  @override Future<PrintingInfo> info()async=>const PrintingInfo(canRaster:false,canPrint:true);
  @override Future<bool> layoutPdf(Printer? printer,LayoutCallback onLayout,String name,PdfPageFormat format,
    bool dynamicLayout,bool usePrinterSettings,OutputType outputType,bool forceCustomPrintPaper,bool windowsModernDialog)async{
    calls++;callback=onLayout;return done.future;
  }
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
Future<void> _ready(WidgetTester tester)async{
  for(var frame=0;frame<200;frame++){
    final button=find.widgetWithText(TextButton,'形式を選んで保存・印刷');
    if(button.evaluate().isNotEmpty&&tester.widget<TextButton>(button).onPressed!=null&&find.byType(PdfPreview).evaluate().isNotEmpty)break;
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));await tester.pump(const Duration(milliseconds:20));
  }
  expect(find.byType(PdfPreview),findsOneWidget);
  expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'形式を選んで保存・印刷')).onPressed,isNotNull);
  await tester.pumpAndSettle();
}
Future<void> _mount(WidgetTester tester,ConfirmedOutputFixture f)async{
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final repository=(await tester.runAsync(f.start))!;expect(await tester.runAsync(repository.available),isTrue);
  await tester.pumpWidget(MaterialApp(home:TradeApprovedDocumentPage(repository:repository,scope:confirmedOutputScope(f.wire.envelope))));
  await _ready(tester);
}
Future<void> _close(WidgetTester tester,ConfirmedOutputFixture f,_NativePrinting printing)async{
  if(printing.calls>0&&!printing.done.isCompleted)printing.done.complete(false);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(()=>f.close().timeout(const Duration(seconds:8)));
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();late PrintingPlatform original;
  setUp((){original=PrintingPlatform.instance;});tearDown((){PrintingPlatform.instance=original;});
  testWidgets('confirmed format route is not a native print lease: plain inactive masks both actual parent and child',(tester)async{
    final f=ConfirmedOutputFixture(),printing=_NativePrinting();PrintingPlatform.instance=printing;
    try{
      await _mount(tester,f);final parent=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
      await tester.tap(find.widgetWithText(TextButton,'形式を選んで保存・印刷'));await tester.pumpAndSettle();
      expect(find.byType(TradeDocumentOutputPage),findsOneWidget);final child=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
      expect(await parent(PdfPageFormat.a4),await child(PdfPageFormat.a4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
      expect(find.byType(PdfPreview,skipOffstage:false),findsNothing);
      await expectLater(parent(PdfPageFormat.a4),throwsStateError);await expectLater(child(PdfPageFormat.a4),throwsStateError);
      expect(printing.calls,0);expect(f.wire.rpcs,hasLength(2));expect(tester.takeException(),isNull);
    }finally{await _close(tester,f,printing);}
  });
  testWidgets('only actual child native call permits parent inactive; completed callbacks reject logout intent and paused history',(tester)async{
    for(final invalidation in ['logout intent','paused']){
      final f=ConfirmedOutputFixture(),printing=_NativePrinting();PrintingPlatform.instance=printing;
      try{
        await _mount(tester,f);final parent=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
        await tester.tap(find.widgetWithText(TextButton,'形式を選んで保存・印刷'));await tester.pumpAndSettle();
        final child=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
        final originalBytes=await parent(PdfPageFormat.a4);
        await tester.tap(find.descendant(of:find.byType(TradeDocumentOutputPage),matching:find.widgetWithText(OutlinedButton,'印刷')));await tester.pump();
        expect(printing.calls,1);expect(printing.callback,isNotNull);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        expect(await printing.callback!(PdfPageFormat.a4),originalBytes);
        expect(await parent(PdfPageFormat.a4),originalBytes);expect(await child(PdfPageFormat.a4),originalBytes);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);printing.done.complete(false);await tester.pumpAndSettle();
        await expectLater(printing.callback!(PdfPageFormat.a4),throwsStateError);
        Future<void>? logout;
        if(invalidation=='logout intent'){
          f.wire.holdLogout=Completer<void>();logout=AppAuthMutationGateway.forClient(f.client).signOut();
          expect(f.wire.logoutStarted.isCompleted,isFalse);expect(f.client.auth.currentSession?.accessToken,f.wire.token);
          // Invoke parent first, before a queued notifier or child's guard can
          // clear its cached bytes. Intent must fence the retained builder now.
          final parentRejected=expectLater(parent(PdfPageFormat.a4),throwsStateError);
          final childRejected=expectLater(child(PdfPageFormat.a4),throwsStateError);
          await parentRejected;await childRejected;
        }else{tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);}
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
        expect(find.byType(PdfPreview,skipOffstage:false),findsNothing);
        await expectLater(parent(PdfPageFormat.a4),throwsStateError);await expectLater(child(PdfPageFormat.a4),throwsStateError);
        await expectLater(printing.callback!(PdfPageFormat.a4),throwsStateError);
        final pendingLogout=logout;if(pendingLogout!=null){f.wire.holdLogout!.complete();await tester.pump();await tester.runAsync(()=>pendingLogout);}
        expect(f.wire.rpcs,hasLength(2));expect(tester.takeException(),isNull);
      }finally{await _close(tester,f,printing);}
    }
  });
}
