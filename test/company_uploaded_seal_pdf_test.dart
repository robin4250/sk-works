import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/domain/company_seal_snapshot.dart';
import 'package:sk_works/domain/invoice_engine.dart';
import 'package:sk_works/features/invoices/invoice_pdf_service.dart';
import 'package:sk_works/features/invoices/invoice_settings_repository.dart';
import 'package:sk_works/features/invoices/invoice_order_acceptance_pdf.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';
import 'package:sk_works/features/payroll/payment_order_pdf.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const png = 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAALUlEQVR4nO3OIQEAAAwEoetf+hdjBoWlVat9mYCAgICAgICAgICAgICAwHfgAIP/+kx2iamjAAAAAElFTkSuQmCC';
  final snapshot = <String, dynamic>{'version': 2, 'style': 'uploaded_png', 'name': '検証株式会社',
    'company_id': '00000000-0000-0000-0000-000000000001',
    'png_version_id': '00000000-0000-0000-0000-000000000002', 'png_base64': png,
    'png_sha256': '30ca1a5ef40b92ff14e0d5f9b4a2a9930ae2013a6cd9d7c4b636e3e70daa58fc'};
  test('uploaded snapshot validates frozen content and does not change old metadata', () {
    final seal = CompanySealSnapshot.fromJson(snapshot);
    expect(seal.uploadedPng!.base64, png);
    expect(CompanySealSnapshot.forPreview({'id':snapshot['company_id'],'name':snapshot['name'],'company_seal_uploaded_snapshot':snapshot}).uploadedPng!.sha256,seal.uploadedPng!.sha256);
    expect(() => CompanySealSnapshot.forPreview({'id':'another-company','name':snapshot['name'],'company_seal_uploaded_snapshot':snapshot}),throwsStateError);
    expect(CompanySealSnapshot.fromJson(null).style, 'legacy');
    expect(CompanySealSnapshot.fromJson({'version': 1, 'style': 'legacy', 'name': '旧会社'}).name, '旧会社');
    expect(() => CompanySealSnapshot.fromJson({...snapshot, 'png_sha256': 'wrong'}), throwsFormatException);
    expect(() => CompanySealSnapshot.fromJson({...snapshot, 'version': 1}), throwsStateError);
  });
  test('invoice payroll payment order and acceptance use frozen PNG in common PDF path', () async {
    final seal = CompanySealSnapshot.fromJson(snapshot);
    final font = await CompanySealPdf.loadFont();
    final output = Directory('build/company-uploaded-seal-proof')..createSync(recursive: true);
    final invoice = InvoiceCalculationResult(customerId: '取引会社', billingPeriod: '2026年10月',
      detailMode: InvoiceDetailMode.consolidatedOnly, siteCalculations: const [],
      taxRateBps: 1000, subtotalYenOverride: 12000, companySealSnapshot: seal);
    final invoiceBytes = await InvoicePdfService.buildPdf([invoice], regularFont: font, boldFont: font,
      settings: const InvoiceSettingsData(companyName: '変更後の会社', taxRate: 10, welfareRate: 0,
        templateTitle: '請求書', footerNote: '', bankName: '', bankBranch: '', bankAccountType: '',
        bankAccountNumber: '', bankAccountHolder: ''));
    File('${output.path}/invoice.pdf').writeAsBytesSync(invoiceBytes);
    final payroll = PayrollStatementRecord(id: 'preview', companyName: '変更後の会社', workerName: '検証太郎',
      periodStart: DateTime(2026,10), periodEnd: DateTime(2026,10,31), grossPay: 12000, deductions: 0, netPay: 12000,
      detail: {'基本給':12000,'pay_type':'daily','company_seal_enabled':true,'company_seal_snapshot':snapshot});
    File('${output.path}/payroll.pdf').writeAsBytesSync(await PayrollPdfService.buildPdf(payroll, regularFont:font,boldFont:font));
    final payment = PaymentCertificateRecord(id: '', partnerCompanyName: '協力会社', payerCompanyName: '変更後の会社',
      periodStart:DateTime(2026,10),periodEnd:DateTime(2026,10,31),grossAmount:12000,deductions:0,netAmount:12000,
      status:'finalized',revision:1,companySealSnapshot:seal);
    File('${output.path}/payment.pdf').writeAsBytesSync(await PaymentCertificatePdfService.buildPdf(payment,regularFont:font,boldFont:font));
    for (final kind in ['order','acceptance']) {
      final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':{
        'version':1,'kind':kind,'month':'2026-10','issue_date':'2026-10-15','order_date':'2026-10-15',
        'period_start':'2026-10-01','period_end':'2026-10-31','total_amount_yen':12000,'tax_amount_yen':1091,
        'work_name':'検証工事','work_address':'東京都','intro_text':'発注します','payment_conditions':'翌月末','notes':'',
        'issuer':{'name':'検証株式会社','address':'東京都','corporate_number':'1234567890123','representative_name':'検証太郎'},
        'counterparty':{'name':'協力会社','address':'東京都','corporate_number':'1234567890124','representative_name':'検証次郎'},
        'company_seal_enabled':true,'company_seal_snapshot':snapshot,
      }});
      final doc=pw.Document(theme:pw.ThemeData.withFont(base:font,bold:font));
      if(kind=='order') { await PaymentOrderPdf.append(doc,attachment,regularFont:font,boldFont:font); }
      else { await InvoiceOrderAcceptancePdf.append(doc,attachment,regularFont:font,boldFont:font); }
      File('${output.path}/$kind.pdf').writeAsBytesSync(await doc.save());
    }
    for(final name in ['invoice','payroll','payment','order','acceptance']) {
      expect(File('${output.path}/$name.pdf').lengthSync(),greaterThan(1000));
    }
  });
  test('acceptance keeps existing legacy Reisho and bundled PNG styles', () async {
    for (final style in ['legacy','aoyagi_reisho','png_sumida_v1_standard']) {
      final name=style=='png_sumida_v1_standard'?'すみだ建設株式会社':'株式会社テスト建設';
      final saved={'version':1,'style':style,'name':name,
        if(style=='png_sumida_v1_standard')'company_id':'0f117273-0a06-4a2f-85ec-720a3c9f4cf4'};
      final attachment=TradeDocumentAttachment.fromJson({'version':1,'payload':{
        'version':1,'kind':'acceptance','month':'2026-10','issue_date':'2026-10-15','order_date':'2026-10-15',
        'work_name':'検証工事','notes':'','issuer':{'name':name,'address':'東京都','corporate_number':'1234567890123','representative_name':'検証太郎'},
        'counterparty':{'name':'協力会社','address':'東京都','corporate_number':'1234567890124','representative_name':'検証次郎'},
        'company_seal_enabled':true,'company_seal_snapshot':saved,
      }});
      final font=await CompanySealPdf.loadFont();
      final doc=pw.Document(theme:pw.ThemeData.withFont(base:font,bold:font));
      await InvoiceOrderAcceptancePdf.append(doc,attachment,regularFont:font,boldFont:font);
      expect((await doc.save()).length,greaterThan(1000));
    }
  });

}
