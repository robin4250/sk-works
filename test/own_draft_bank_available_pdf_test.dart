import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/own_draft_bank_admission.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'own_draft_bank_admission_test.dart' as fixture;
void main(){
 test('available own bank renders a real synthetic PDF with live source lease',()async{
  var current=true;
  const bank={'bank_name':'SYNTHETIC BANK','branch_name':'SYNTHETIC BRANCH','account_type':'普通','account_number':'0000001','account_holder':'SYNTHETIC HOLDER'};
  final admission=OwnDraftBankAdmission.decode({...fixture.response('available'),'personal_revision':1,'bank_account':bank},actor:fixture.actor,sid:fixture.sid,statement:fixture.id,revision:1,current:()=>current).withLease(()=>current);
  final source=PayrollStatementRecord(id:fixture.id,companyName:'SYNTHETIC COMPANY',workerName:'SYNTHETIC WORKER',periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),grossPay:100,deductions:10,netPay:90,revision:1,workflowState:'draft',detail:{'company_seal_enabled':false,'基本給':100,'所得税':10,'bank_account':{'bank_name':'MUST NOT RENDER LEGACY'},'銀行名':'MUST NOT RENDER LEGACY'});
  final own=asOwnDraftStatement(source,admission:admission);expect(own.detail['bank_account'],bank);expect(own.detail.containsKey('銀行名'),false);
  final font=pw.Font.ttf(ByteData.sublistView(await File('assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytes()));
  final bytes=await PayrollPdfService.buildPdf(own,regularFont:font,boldFont:font,expenseDetails:ExpenseDocumentDetails(kind:ExpenseDocument.payroll,documentId:fixture.id,subjectId:fixture.actor,month:source.periodStart,claims:ExpenseClaims(companyId:'synthetic',claims:const [])));
  expect(String.fromCharCodes(bytes.take(5)),'%PDF-');expect(bytes.length,greaterThan(10000));expect(admission.permits(fixture.id,1),true);
  const output=String.fromEnvironment('SKO_SYNTHETIC_PAYROLL_OUTPUT');
  if(output.isNotEmpty){await Directory(output).create(recursive:true);await File('$output/own-draft-synthetic-available.pdf').writeAsBytes(bytes);}
  current=false;expect(admission.permits(fixture.id,1),false);
 });
}
