import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
void main(){
 test('saved inactive company settlement source renders caption with all five bank fields',()async{
  const id='30000000-0000-4000-8000-000000000001',actor='10000000-0000-4000-8000-000000000001';
  const bank={'bank_name':'SYNTHETIC SETTLEMENT BANK','branch_name':'SYNTHETIC BRANCH','account_type':'普通','account_number':'0000001','account_holder':'SYNTHETIC HOLDER'};
  final saved=PayrollStatementRecord(id:id,companyName:'SYNTHETIC COMPANY',workerName:'SYNTHETIC INACTIVE WORKER',periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),grossPay:100,deductions:10,netPay:90,revision:3,workflowState:'finalized',detail:{'company_seal_enabled':false,'基本給':100,'所得税':10,'bank_account':bank,'personal_bank_basis':{'source_kind':'company_worker_inactive_v1','revision':123,'binding_sha256':'a'*64}});
  final font=pw.Font.ttf(ByteData.sublistView(await File('assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytes()));
  final bytes=await PayrollPdfService.buildPdf(saved,regularFont:font,boldFont:font,expenseDetails:ExpenseDocumentDetails(kind:ExpenseDocument.payroll,documentId:id,subjectId:actor,month:saved.periodStart,claims:ExpenseClaims(companyId:'synthetic',claims:const [])));
  expect(String.fromCharCodes(bytes.take(5)),'%PDF-');expect(bytes.length,greaterThan(10000));
  expect(saved.detail['bank_account'],bank);expect(saved.ownDraftBankPurpose,false);
  const output=String.fromEnvironment('SKO_SYNTHETIC_PAYROLL_OUTPUT');
  if(output.isNotEmpty){await Directory(output).create(recursive:true);await File('$output/saved-inactive-company-bank.pdf').writeAsBytes(bytes);}
 });
}
