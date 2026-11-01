import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/payroll/own_draft_bank_admission.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
import 'package:sk_works/features/payroll/payroll_statements_page.dart';
import 'package:sk_works/features/expenses/expense_detail_pdf.dart';
import 'package:sk_works/features/expenses/expense_document_repository.dart';
import 'package:sk_works/features/expenses/expense_claim.dart';
import 'own_draft_bank_admission_test.dart' as fixture;
import 'own_draft_bank_preview_test.dart' as preview_fixture;
class CountingGateway extends preview_fixture.BankGateway {
 int reads=0;
 @override Future<OwnDraftBankAdmission> read(PayrollStatementRecord statement){reads++;return super.read(statement);}
}
void main(){
 test('source-generation lease rejects held PDF and retained old callback',()async{
  var generation=0;
  final lease=OwnDraftBankAdmission.decode(fixture.response('confirmed_absent'),actor:fixture.actor,sid:fixture.sid,statement:fixture.id,revision:1,current:()=>true).withLease(()=>generation==0);
  final source=PayrollStatementRecord(id:fixture.id,companyName:'Synthetic',workerName:'Synthetic',periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),grossPay:100,deductions:10,netPay:90,revision:1,workflowState:'draft',detail:{'company_seal_enabled':false,'基本給':100,'所得税':10});
  final old=asOwnDraftStatement(source,admission:lease);
  final expenses=ExpenseDocumentDetails(kind:ExpenseDocument.payroll,documentId:fixture.id,subjectId:fixture.actor,month:source.periodStart,claims:ExpenseClaims(companyId:'synthetic',claims:const []));
  final font=pw.Font.ttf(ByteData.sublistView(await File('assets/fonts/company-seal/NotoSansJP-Bold.ttf').readAsBytes()));
  Future<dynamic> oldCallback()=>PayrollPdfService.buildPdf(old,expenseDetails:expenses,regularFont:font,boldFont:font);
  final held=oldCallback();generation++;
  final rejected=isA<StateError>().having((e)=>e.message,'bank guard',contains('個人口座'));
  await expectLater(held,throwsA(rejected));expect(lease.permits(fixture.id,1),false);
  await expectLater(oldCallback(),throwsA(rejected));
 });
 test('explicit management is hidden rather than absent; own finalized default unchanged',(){
  final managed=asManagementBankHiddenStatement(fixture.row(state:'finalized'));
  expect(managed.managementBankHidden,true);expect(managed.detail['bank_account'],isEmpty);expect(managed.detail.containsKey('銀行名'),false);
  final ownFinal=fixture.row(state:'finalized');expect(asOwnDraftStatement(ownFinal),same(ownFinal));expect(ownFinal.managementBankHidden,false);
 });
 testWidgets('authorized self fallback initializes resolver after manager initial purpose',(tester)async{
  final gateway=CountingGateway();final managed=asManagementBankHiddenStatement(fixture.row());final own=asOwnDraftStatement(fixture.row());
  final source=PayrollStatementSourceRepository(readManagement:(_)async=>throw const PostgrestException(message:'synthetic',code:'42501'),readSelf:()async=>[own],readConfirmation:(_)async=>throw StateError('unused'));
  await tester.pumpWidget(MaterialApp(home:PayrollStatementPreviewPage(statement:managed,sourceRepository:source,ownBankGateway:gateway)));await tester.pumpAndSettle();
  expect(gateway.reads,1);expect(find.textContaining('支給額 100円'),findsOneWidget);expect(find.textContaining('未登録とは判断せず'),findsOneWidget);
 });
 testWidgets('foreign management target absent from self reader never invokes own resolver',(tester)async{
  final gateway=CountingGateway();final managed=asManagementBankHiddenStatement(fixture.row());
  final source=PayrollStatementSourceRepository(readManagement:(_)async=>throw const PostgrestException(message:'synthetic',code:'42501'),readSelf:()async=>[],readConfirmation:(_)async=>throw StateError('unused'));
  await tester.pumpWidget(MaterialApp(home:PayrollStatementPreviewPage(statement:managed,sourceRepository:source,ownBankGateway:gateway)));await tester.pumpAndSettle();
  expect(gateway.reads,0);expect(find.textContaining('再取得できませんでした'),findsWidgets);
 });
}
