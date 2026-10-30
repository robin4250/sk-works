import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/shared/trade_document_form_renderer.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'trade_document_form_draft_test.dart' show formBody;

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 final directory=Platform.environment['TRADE_DEFAULTS_PDF_OUTPUT_DIR'];
 for(final kind in ['order','acceptance']){
  for(final name in ['すみだ建設株式会社','SK','株式会社長い会社名称を省略せずに表示する建設工事会社']){
   test('actual $kind issuer block and new agreed defaults ($name)',()async{
    final p=formBody()..['kind']=kind;
    p['acceptance_text']='注文内容を承諾します。';
    p['issuer']={'name':name,'address':'東京都墨田区横川1-9-1','representative_name':'齊藤竜一','phone':'03-1111-2222','fax':'03-3333-4444'};
    p['company_seal_enabled']=true;
    p['company_seal_snapshot']={'version':1,'style':'legacy','name':name};
    final value=TradeDocumentFormDraft.fromPayload(p,allowAmountEditing:false,initializeDefaults:true,initializeExtendedFields:true).payload;
    final before=jsonEncode(value),bytes=await TradeDocumentFormRenderer.canonical(value);
    expect(bytes.length,greaterThan(1000));expect(jsonEncode(value),before);
    if(directory!=null){Directory(directory).createSync(recursive:true);File('$directory/$kind-${name=='SK'?'short':name.startsWith('すみだ')?'normal':'long'}.pdf').writeAsBytesSync(bytes);}
   });
  }
 }
 test('all invoice detail pages precede acceptance front and complete terms',()async{
  const settings=InvoiceSettingsData(companyName:'すみだ建設株式会社',taxRate:10,welfareRate:0,templateTitle:'請求書',footerNote:'',bankName:'',bankBranch:'',bankAccountType:'',bankAccountNumber:'',bankAccountHolder:'',companySealEnabled:false);
  final invoice=InvoiceEngine.calculate(customerId:'登録取引会社',invoiceId:'pagination-fixture',billingPeriod:'2026年10月',detailMode:InvoiceDetailMode.consolidatedOnly,
   sites:[SiteInvoiceCalculation(siteId:'site',siteName:'全明細を保持する工事',lines:List.generate(36,(i)=>InvoiceLine(label:'工事${i+1}',quantity:1,unitPriceYen:1000)))],taxRateBps:1000);
  final p=formBody()..['kind']='acceptance';p['acceptance_text']='注文内容を承諾します。';
  final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':p});
  final font=await CompanySealPdf.loadFont();
  final bytes=await InvoicePdfService.buildPdf([invoice],settings:settings,regularFont:font,boldFont:font,
   approvalsByInvoice:const {'pagination-fixture':[]},acceptanceByInvoice:{'pagination-fixture':attachment});
  expect(invoice.grandTotalYen,39600);
  if(directory!=null){Directory(directory).createSync(recursive:true);File('$directory/invoice-multipage.pdf').writeAsBytesSync(bytes);}
 });
}
