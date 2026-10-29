import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// The exact pinned 5.15.1 public platform method signatures are used here.
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_dialog.dart';
import 'package:sk_works/features/shared/trade_document_confirmation_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_output_page.dart';
import 'trade_document_confirmed_output_session_test.dart' show ConfirmedOutputFixture,confirmedOutputScope;

class _HostFixture extends ConfirmedOutputFixture{
  VoidCallback? beforeRepository;
  @override Future<SupabaseTradeConfirmationRepository> start()async{
    await login();beforeRepository?.call();return repository=SupabaseTradeConfirmationRepository(client);
  }
}
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
  expect(find.byType(PdfPreview),findsOneWidget,reason:'Confirmed render stage: ${tester.widgetList<Text>(find.byType(Text)).map((text)=>text.data).join(" | ")}');
  expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'形式を選んで保存・印刷')).onPressed,isNotNull);
  await tester.pumpAndSettle();
}
Future<void> _mount(WidgetTester tester,ConfirmedOutputFixture f)async{
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // CompanySealPdf caches its asset Future. Create it in the real zone so the
  // next Widget test never inherits a completed Future owned by an old FakeAsync.
  await tester.runAsync(()=>CompanySealPdf.loadFont().timeout(const Duration(seconds:5)));
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
    for(final invalidation in ['logout intent','paused','fresh SDK before host listener']){
      final f=_HostFixture(),printing=_NativePrinting();PrintingPlatform.instance=printing;
      LayoutCallback? retainedParent;StreamSubscription<AuthState>? probe;
      var probeArmed=false,earlyBytes=false;Object? earlyError;
      if(invalidation=='fresh SDK before host listener'){
        f.beforeRepository=(){probe=f.client.auth.onAuthStateChange.listen((event){
          final callback=retainedParent;
          if(!probeArmed||callback==null||event.event!=AuthChangeEvent.signedIn||event.session?.accessToken!=f.wire.token)return;
          unawaited(Future.sync(()=>callback(PdfPageFormat.a4)).then<void>((_){earlyBytes=true;},onError:(Object error){earlyError=error;}));
        });};
      }
      try{
        debugPrint('confirmed-host-stage $invalidation mount');
        await _mount(tester,f);debugPrint('confirmed-host-stage $invalidation mounted');final parent=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;retainedParent=parent;
        await tester.tap(find.widgetWithText(TextButton,'形式を選んで保存・印刷'));await tester.pumpAndSettle();
        final child=tester.widget<PdfPreview>(find.byType(PdfPreview)).build;
        debugPrint('confirmed-host-stage $invalidation child mounted');
        final originalBytes=await parent(PdfPageFormat.a4);
        await tester.tap(find.descendant(of:find.byType(TradeDocumentOutputPage),matching:find.widgetWithText(OutlinedButton,'印刷')));await tester.pump();
        debugPrint('confirmed-host-stage $invalidation native entered');
        expect(printing.calls,1);expect(printing.callback,isNotNull);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        expect(await printing.callback!(PdfPageFormat.a4),originalBytes);
        expect(await parent(PdfPageFormat.a4),originalBytes);expect(await child(PdfPageFormat.a4),originalBytes);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);printing.done.complete(false);await tester.pumpAndSettle();
        await expectLater(printing.callback!(PdfPageFormat.a4),throwsStateError);
        debugPrint('confirmed-host-stage $invalidation native ended');
        Future<void>? logout;
        if(invalidation=='logout intent'){
          // Keep the actual SDK mutation, HTTP gate and completion in the
          // real zone. Awaiting its FakeAsync-owned completion inside runAsync
          // would strand the SDK continuation after releasing the HTTP gate.
          await tester.runAsync(()async{
            f.wire.holdLogout=Completer<void>();logout=AppAuthMutationGateway.forClient(f.client).signOut();
            expect(f.wire.logoutStarted.isCompleted,isFalse);expect(f.client.auth.currentSession?.accessToken,f.wire.token);
            // Check intent before awaiting SDK dispatch. Quarantine is sync.
            final parentRejected=expectLater(parent(PdfPageFormat.a4),throwsStateError);
            final childRejected=expectLater(child(PdfPageFormat.a4),throwsStateError);
            await parentRejected;await childRejected;
            await f.wire.logoutStarted.future.timeout(const Duration(seconds:5));
          });
          debugPrint('confirmed-host-stage $invalidation intent assertions passed');
        }else if(invalidation=='paused'){tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);}
        else{
          probeArmed=true;f.wire.sid='20000000-0000-4000-8000-000000000099';await tester.runAsync(f.login);
          await tester.runAsync(()=>Future<void>.delayed(Duration.zero));
          debugPrint('retained-builder-probe returned_bytes=$earlyBytes state_error=${earlyError is StateError}');
          expect(earlyError,isA<StateError>(),reason:'The earlier real SDK listener calls the retained parent builder before the host subscriber');
          expect(earlyBytes,isFalse);
        }
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);await tester.pumpAndSettle();
        expect(find.byType(PdfPreview,skipOffstage:false),findsNothing);
        await expectLater(parent(PdfPageFormat.a4),throwsStateError);await expectLater(child(PdfPageFormat.a4),throwsStateError);
        await expectLater(printing.callback!(PdfPageFormat.a4),throwsStateError);
        final pendingLogout=logout;if(pendingLogout!=null){debugPrint('confirmed-host-stage $invalidation logout release');await tester.runAsync(()async{f.wire.holdLogout!.complete();await pendingLogout.timeout(const Duration(seconds:5));});await tester.pump();debugPrint('confirmed-host-stage $invalidation logout completed');}
        expect(f.wire.rpcs,hasLength(2));expect(tester.takeException(),isNull);
      }finally{debugPrint('confirmed-host-stage $invalidation cleanup');final subscription=probe;if(subscription!=null)await tester.runAsync(subscription.cancel);await _close(tester,f,printing);debugPrint('confirmed-host-stage $invalidation cleaned');}
    }
  });
}
