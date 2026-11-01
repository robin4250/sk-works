import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';
import 'package:sk_works/features/shared/trade_document_output_layout.dart';
import 'package:sk_works/features/shared/trade_document_output_page.dart';
import 'package:sk_works/features/shared/trade_document_output_selector.dart';

Map<String,dynamic> _payload(String kind)=>TradeDocumentFormDraft.fromPayload(TradeDocumentTermsSnapshot.initialize({
  'version':1,'kind':kind,'month':'2026-10','issue_date':'2026-09-30','order_date':'2026-09-30',
  'work_name':'Synthetic original contract','work_address':'Synthetic original place',
  'period_start':'2026-10-01','period_end':'2026-10-31','total_amount_yen':110000,'tax_amount_yen':10000,
  'intro_text':'Synthetic order','acceptance_text':'Synthetic acceptance','payment_conditions':'Synthetic original payment','notes':'Synthetic original note',
  'issuer':{'name':'Synthetic issuer'},'counterparty':{'name':'Synthetic partner'},
  'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'Synthetic issuer'},
}),allowAmountEditing:false).payload;
Directory? _temporaryOutputDirectory;
void _write(String name,Uint8List bytes){
  final folder=Platform.environment['TRADE_FORMAT_UI_OUTPUT_DIR']??
    (_temporaryOutputDirectory??=Directory.systemTemp.createTempSync('trade-format-ui-proof-')).path;
  Directory(folder).createSync(recursive:true);File('$folder/$name.pdf').writeAsBytesSync(bytes);
}
Future<void> _drainRender(WidgetTester tester)async{
  // Real font/image/PDF callbacks must progress; fake-time settlement alone
  // cannot finish them. This bounded loop never bypasses the busy-state check.
  for(var frame=0;frame<200&&find.byType(LinearProgressIndicator).evaluate().isNotEmpty;frame++){
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:10)));
    await tester.pump(const Duration(milliseconds:20));
  }
  expect(find.byType(LinearProgressIndicator),findsNothing,reason:'Actual format rendering must finish');
  await tester.pumpAndSettle();
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll((){
    final temporaryOutputDirectory=_temporaryOutputDirectory;
    if(temporaryOutputDirectory!=null)temporaryOutputDirectory.deleteSync(recursive:true);
  });
  testWidgets('actual dropdown taps send A3 then duplex then original A4 to asynchronous form-only rendering',(tester)async{
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    const channel=MethodChannel('net.nfet.printing');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call)async=>call.method=='printingInfo'?{'canRaster':false}:null);
    final payload=_payload('order'),before=jsonEncode(payload);
    final canonical=(await tester.runAsync(()=>TradeDocumentFormRenderer.canonical(payload).timeout(const Duration(seconds:10))))!;
    final original=Uint8List.fromList(canonical);var checks=0;
    try{
      await tester.pumpWidget(MaterialApp(home:TradeDocumentOutputPage(payload:payload,canonicalBytes:canonical,requireScope:(){checks++;})));
      await tester.pumpAndSettle();
      final sequence=<TradeDocumentOutputLayout,String>{
        TradeDocumentOutputLayout.a3Landscape:'A3横・見開き1枚（2ページを左右に配置）',
        TradeDocumentOutputLayout.a4Duplex:'A4 表裏1枚（長辺とじ推奨）',
        TradeDocumentOutputLayout.a4TwoPages:'A4縦・2ページ（帳票＋契約条項）',
      };
      final actualOrder=<TradeDocumentOutputLayout>[];
      for(final choice in sequence.entries){
        final beforeChecks=checks;
        await tester.tap(find.byType(DropdownButtonFormField<TradeDocumentOutputLayout>));await tester.pumpAndSettle();
        await tester.tap(find.text(choice.value).last);await tester.pump();await _drainRender(tester);
        final selected=tester.widget<TradeDocumentOutputSelector>(find.byType(TradeDocumentOutputSelector)).value;
        actualOrder.add(selected);expect(selected,choice.key);expect(checks,greaterThan(beforeChecks));
        final bytes=await tester.widget<PdfPreview>(find.byType(PdfPreview)).build(PdfPageFormat.a4);
        expect(bytes,isNotEmpty);_write('ui-${choice.key.name}',bytes);
        if(choice.key==TradeDocumentOutputLayout.a4TwoPages){expect(bytes,original);}else{expect(bytes, isNot(equals(original)));}
        expect(canonical,original);expect(jsonEncode(payload),before);expect(tester.takeException(),isNull);
      }
      expect(actualOrder,sequence.keys.toList());
    }finally{
      await tester.pumpWidget(const SizedBox.shrink());tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    }
  });
  for(final kind in ['order','acceptance']){
    test('actual $kind financial builder remains three A4 pages after all form-only formats',()async{
      final payload=_payload(kind),before=jsonEncode(payload),font=await CompanySealPdf.loadFont();
      final canonical=await TradeDocumentFormRenderer.canonical(payload);
      final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':payload});
      final invoice=InvoiceEngine.calculate(customerId:'Synthetic partner',invoiceId:'fixture-invoice',billingPeriod:'2026年10月',
        detailMode:InvoiceDetailMode.consolidatedOnly,sites:const [SiteInvoiceCalculation(siteId:'synthetic-site',siteName:'Synthetic work',lines:[InvoiceLine(label:'Synthetic work',quantity:1,unitPriceYen:100000)])],taxRateBps:1000);
      const settings=InvoiceSettingsData(companyName:'Synthetic issuer',taxRate:10,welfareRate:0,templateTitle:'請求書',footerNote:'',bankName:'',bankBranch:'',bankAccountType:'',bankAccountNumber:'',bankAccountHolder:'',companySealEnabled:false);
      final payment=PaymentCertificateRecord(id:'fixture-payment',partnerCompanyName:'Synthetic partner',payerCompanyName:'Synthetic issuer',periodStart:DateTime(2026,10,1),periodEnd:DateTime(2026,10,31),grossAmount:110000,deductions:0,netAmount:110000,status:'preview',revision:1,payerCompanySealEnabled:false);
      Future<Uint8List> build(TradeDocumentAttachment? form)=>kind=='order'
        ?PaymentCertificatePdfService.buildPdf(payment,regularFont:font,boldFont:font,orderAttachment:form)
        :InvoicePdfService.buildPdf([invoice],settings:settings,regularFont:font,boldFont:font,allowLegacyApprovalInitialization:false,
          approvalsByInvoice:const {'fixture-invoice':[]},acceptanceByInvoice:{'fixture-invoice':form});
      _write('$kind-financial-baseline',await build(null));_write('$kind-financial-before',await build(attachment));
      for(final mode in TradeDocumentOutputLayout.values){
        _write('$kind-form-${mode.name}',await TradeDocumentFormRenderer.output(payload,layout:mode,canonicalBytes:canonical));
        expect(jsonEncode(payload),before);expect(invoice.grandTotalYen,110000);expect(payment.netAmount,110000);
      }
      _write('$kind-financial-after',await build(attachment));expect(jsonEncode(payload),before);
    });
  }
}
