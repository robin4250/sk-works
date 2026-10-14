import 'package:sk_works/features/expenses/expense_claim.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/shared/company_seal_pdf.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/payroll/payment_certificate_pdf_service.dart';
import 'package:sk_works/features/payroll/payment_certificate_repository.dart';

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 TradeDocumentAttachment order({bool long=false})=>TradeDocumentAttachment.fromJson({'version':1,'payload':{
  'version':1,'kind':'order','month':'2026-10','issue_date':'2026-10-15',
  'work_name':long?List.filled(120,'工事').join():'内装補修工事','work_address':long?List.filled(120,'住所').join():'東京都墨田区1-2-3',
  'period_start':'2026-10-01','period_end':'2026-10-31','total_amount_yen':110000,'tax_amount_yen':10000,
  'intro_text':long?List.filled(100,'発注条件').join():'発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
  'payment_conditions':long?List.filled(100,'完了確認').join():'工事完了確認後、2026年11月末日までに乙の指定口座に振り込む。',
  'notes':long?List.filled(200,'特記事項').join().substring(0,600):'当月の合意事項を記録します。',
  'issuer':{'name':'株式会社発注','address':long?List.filled(120,'住所').join():'東京都1-1-1','corporate_number':'1234567890123','representative_name':'発注 太郎'},
  'counterparty':{'name':long?List.filled(30,'株式会社').join():'株式会社下請','address':long?List.filled(120,'住所').join():'神奈川県2-2-2','corporate_number':'9876543210987','representative_name':long?List.filled(40,'代表').join():'下請 次郎'},
  'company_seal_enabled':true,'company_seal_snapshot':{'version':1,'style':'legacy','name':'株式会社発注'},
 }});
 test('monthly appendix is opt-in and preserves the adopted first page and amounts',()async{
  final font=await CompanySealPdf.loadFont();
  final record=PaymentCertificateRecord(id:'fixture',partnerCompanyName:'株式会社下請',payerCompanyName:'株式会社発注',
   periodStart:DateTime(2026,10,1),periodEnd:DateTime(2026,10,31),grossAmount:110000,deductions:0,netAmount:110000,status:'draft',revision:1,payerCompanySealEnabled:false);
  final output=Platform.environment['SKO_PDF_OUTPUT_DIR'];
  final expenses=ExpenseDocumentDetails(kind:ExpenseDocument.paymentCertificate,documentId:'fixture',subjectId:'partner',month:DateTime(2026,10),
    claims:ExpenseClaims(companyId:'company',claims:[ExpenseClaim(id:'expense',companyId:'company',applicantId:'worker',applicantName:'検証者',
      incurredOn:DateTime(2026,10,1),submittedAt:DateTime(2026,10,1),description:'経費の実頁順検証',amountYen:500,
      approval:ExpenseApproval.approved,allocation:ExpenseAllocation(ExpenseCategory.subcontractor,counterpartyId:'partner',counterpartyName:'株式会社下請'))]));
  for(final variant in ['legacy','order','long','expenses']){
   final bytes=await PaymentCertificatePdfService.buildPdf(record,regularFont:font,boldFont:font,
     orderAttachment:variant=='legacy'?null:order(long:variant=='long'),expenseDetails:variant=='expenses'?expenses:null);
   expect(bytes.length,greaterThan(1000));
   if(output!=null){Directory(output).createSync(recursive:true);File('$output/payment-$variant.pdf').writeAsBytesSync(bytes);}
  }
 });
 test('wrong month appendix is refused',()async{
  final font=await CompanySealPdf.loadFont();
  final record=PaymentCertificateRecord(id:'fixture',partnerCompanyName:'下請',periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),grossAmount:110000,deductions:0,netAmount:110000,status:'draft',revision:1,payerCompanySealEnabled:false);
  await expectLater(PaymentCertificatePdfService.buildPdf(record,regularFont:font,boldFont:font,orderAttachment:order()),throwsStateError);
 });
}
