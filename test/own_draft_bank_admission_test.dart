import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/own_draft_bank_admission.dart';
import 'package:sk_works/features/payroll/payroll_statement_repository.dart';
import 'package:sk_works/features/payroll/payroll_pdf_service.dart';
import 'package:sk_works/features/payroll/payroll_statement_source_repository.dart';
const actor='10000000-0000-4000-8000-000000000001',sid='20000000-0000-4000-8000-000000000001',id='30000000-0000-4000-8000-000000000001';
PayrollStatementRecord row({String state='draft'})=>PayrollStatementRecord(id:id,companyName:'Synthetic',workerName:'Synthetic',periodStart:DateTime(2026,11,1),periodEnd:DateTime(2026,11,30),grossPay:100,deductions:10,netPay:90,revision:1,workflowState:state,detail:{'bank_account':{'bank_name':'LEGACY'},'銀行名':'LEGACY','account_number':'LEGACY'});
Map<String,dynamic> response(String state)=>{'protocol_version':1,'actor_id':actor,'session_id':sid,'statement_id':id,'statement_revision':1,'state':state,'personal_revision':state=='unavailable'?null:0,'bank_account':null,'reason_code':state=='unavailable'?'basis_unavailable':null};
void main(){
 test('strict absent/unavailable are distinct and stale lease revokes admission',(){
  var current=true;
  final absent=OwnDraftBankAdmission.decode(response('confirmed_absent'),actor:actor,sid:sid,statement:id,revision:1,current:()=>current);
  expect(absent.bankFor(id,1),isEmpty);expect(absent.permits(id,2),false);
  final unavailable=OwnDraftBankAdmission.decode(response('unavailable'),actor:actor,sid:sid,statement:id,revision:1,current:()=>current);
  expect(unavailable.permits(id,1),false);expect(()=>unavailable.bankFor(id,1),throwsStateError);
  for(final bad in [{...response('confirmed_absent'),'extra':true},{...response('confirmed_absent'),'personal_revision':false},{...response('confirmed_absent'),'state':'unknown'},{...response('confirmed_absent'),'session_id':'foreign'}]){
   expect(()=>OwnDraftBankAdmission.decode(bad,actor:actor,sid:sid,statement:id,revision:1,current:()=>true),throwsFormatException);
  }
  current=false;expect(absent.permits(id,1),false);
 });
 test('only own draft removes all legacy aliases; finalized snapshot unchanged',(){
  final draft=asOwnDraftStatement(row());expect(draft.ownDraftBankPurpose,true);expect(draft.detail,isEmpty);expect(draft.netPay,90);
  final saved=row(state:'finalized');expect(identical(asOwnDraftStatement(saved),saved),true);expect(saved.detail['銀行名'],'LEGACY');
 });
 test('service rejects unresolved own draft before loading expenses or fonts',()async{
  await expectLater(PayrollPdfService.buildPdf(asOwnDraftStatement(row())),throwsStateError);
 });
 test('finalized source bypasses draft resolver and preserves frozen bank',()async{
  final original=asOwnDraftStatement(row());
  // A final source never requests current draft bank and preserves frozen content.
  final finalSource=PayrollStatementSourceRepository(readManagement:(_)async=>[row(state:'finalized')],readSelf:()async=>[],readConfirmation:(_)async=>throw StateError('must not read confirmation'));
  final saved=await finalSource.load(original);expect(saved.statement.isDraft,false);expect(saved.statement.detail['銀行名'],'LEGACY');
 });
}
