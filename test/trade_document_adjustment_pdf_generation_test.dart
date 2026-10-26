import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/domain/trade_document_adjustment_snapshot.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 final fontPath=Platform.environment['SKO_PDF_FONT_PATH'];
 test('synthetic final plus minus PDFs preserve adopted header footer and exact totals',() async {
  final font=pw.Font.ttf(ByteData.sublistView(await File(fontPath!).readAsBytes()));
  final output=Directory(Platform.environment['SKO_PDF_OUTPUT_DIR'] ?? Directory.systemTemp.createTempSync('sko-adjustment-proof-').path);
  output.createSync(recursive:true);
  const items=[SavedTradeDocumentAdjustment(id:'11111111-1111-4111-8111-111111111111',title:'追加支給',amountYen:500,sign:'plus',calculationMode:'settlement_yen'),
   SavedTradeDocumentAdjustment(id:'22222222-2222-4222-8222-222222222222',title:'材料控除',amountYen:200,sign:'minus',calculationMode:'settlement_yen')];
  const settings=InvoiceSettingsData(companyName:'検証株式会社',taxRate:10,welfareRate:5,templateTitle:'請求書',footerNote:'合成データによる内部検証',
   bankName:'検証銀行',bankBranch:'検証支店',bankAccountType:'普通',bankAccountNumber:'0000000',bankAccountHolder:'ケンショウ',companySealEnabled:false);
  for(final adjusted in [false,true]) {
   final name=adjusted?'adjusted':'baseline';
   final invoice=InvoiceEngine.calculate(customerId:'検証取引会社',billingPeriod:'2026年10月',invoiceNumber:'TEST-001',issueDate:DateTime(2026,10,31),
    detailMode:InvoiceDetailMode.siteBreakdownOnInvoice,taxRateBps:1000,sites:const [SiteInvoiceCalculation(siteId:'fixture-site',siteName:'検証現場',
     lines:[InvoiceLine(label:'検証作業',quantity:1,unitPriceYen:10000)],welfareRateBps:500)],
    subtotalYenOverride:10500,taxYenOverride:1050,grandTotalYenOverride:adjusted?11850:11550,documentAdjustments:adjusted?items:const []);
   final bytes=await InvoicePdfService.buildPdf([invoice],settings:settings,regularFont:font,boldFont:font,acceptanceByInvoice:const {});
   File('${output.path}/invoice_$name.pdf').writeAsBytesSync(bytes);
   final certificate=PaymentCertificateRecord(id:'synthetic-fixture',partnerCompanyName:'検証協力会社',payerCompanyName:'検証株式会社',payerCompanySealEnabled:false,
    periodStart:DateTime(2026,10,1),periodEnd:DateTime(2026,10,31),grossAmount:adjusted?12050:11550,deductions:adjusted?200:0,netAmount:adjusted?11850:11550,
    status:'draft',revision:1,documentAdjustments:adjusted?items:const [],lines:const [
     PaymentCertificateLine(siteName:'検証現場',workContent:'検証作業',quantityLabel:'1人',unitPriceYen:10000,amountYen:10000),
     PaymentCertificateLine(siteName:'〃',workContent:'福利厚生費',quantityLabel:'5%',unitPriceYen:0,amountYen:500),
     PaymentCertificateLine(siteName:'〃',workContent:'消費税',quantityLabel:'10%',unitPriceYen:0,amountYen:1050)]);
   File('${output.path}/certificate_$name.pdf').writeAsBytesSync(await PaymentCertificatePdfService.buildPdf(certificate,regularFont:font,boldFont:font));
  }
  final proof=await Process.run('python',['tool/verify_adjustment_pdf_render.py',output.path]);
  expect(proof.exitCode,0,reason:'${proof.stdout}\n${proof.stderr}');
 },skip:fontPath==null?'CI must supply the pinned Japanese TTF for PDF proof.':false);
}
