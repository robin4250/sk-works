import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/trade_document_form_draft.dart';
import 'package:sk_works/domain/trade_document_terms_snapshot.dart';
Map<String,dynamic> formBody()=>TradeDocumentTermsSnapshot.initialize({
 'version':1,'kind':'order','month':'2026-10','issue_date':'2026-09-15','order_date':'2026-09-15','work_name':'実際の工事','work_address':'東京都',
 'period_start':'2026-10-01','period_end':'2026-10-31','total_amount_yen':110000,'tax_amount_yen':10000,'payment_conditions':'合意済み条件','notes':'',
 'issuer':{'name':'登録自社','address':'自社住所'},'counterparty':{'name':'登録協力会社','address':'相手住所'},
 'company_seal_enabled':false,'company_seal_snapshot':{'version':1,'style':'legacy','name':'登録自社'},
});
TradeDocumentFormDraft draft({bool amount=false})=>TradeDocumentFormDraft.fromPayload(formBody(),allowAmountEditing:amount);
void main(){
 test('complete schema and nine rows are added only to the private working copy',(){
  final source=formBody(),before=jsonEncode(source),value=TradeDocumentFormDraft.fromPayload(source,allowAmountEditing:false),p=value.payload;
  expect(p['form_fields'],TradeDocumentFormFields.empty().toJson());expect((p['form_fields']['rows'] as List),hasLength(9));
  expect(p['form_fields']['payments']['advance']['amount_yen'],isNull);expect(p['form_fields']['rows'][0]['quantity'],'');
  p['issuer']['name']='変更';p['form_fields']['rows'][0]['item']='変更';expect(value.payload['issuer']['name'],'登録自社');expect(value.payload['form_fields']['rows'][0]['item'],'');expect(jsonEncode(source),before);
 });
 for(final key in ['issuer','counterparty','company_id','partner_company_id','contract_terms','counterparty_bank','company_seal_snapshot','company_seal_enabled']){
  test('patch cannot change frozen $key',(){expect(()=>draft().withChanges({key:null}),throwsFormatException);});
 }
 test('monthly amounts stay read-only while standalone may accept explicit integer values',(){
  expect(()=>draft().withChanges({'total_amount_yen':120000}),throwsFormatException);expect(()=>draft().withChanges({'tax_amount_yen':0}),throwsFormatException);
  final result=draft(amount:true).withChanges({'total_amount_yen':'120000','tax_amount_yen':10000});result.validateForSave();expect(result.payload['total_amount_yen'],120000);
  expect(()=>draft(amount:true).withChanges({'total_amount_yen':-1}),throwsFormatException);
 });
 test('blank required input is kept while editing and rejected only at save',(){
  final result=draft().withChanges({'work_name':''});expect(result.payload['work_name'],'');expect(result.validateForSave,throwsFormatException);
  expect(()=>draft().withChanges({'issue_date':'2026-02-30'}),throwsFormatException);
 });
 test('row quantities and amounts remain explicit, never recalculate the source total',(){
  final fields=draft().payload['form_fields'] as Map<String,dynamic>;fields['rows'][0]={'item':'実明細','quantity':'1.250','unit':'m2','unit_price_yen':750,'amount_yen':900,'note':'明示入力'};
  final result=draft().withChanges({'form_fields':fields});result.validateForSave();expect(result.payload['total_amount_yen'],110000);expect(result.payload['tax_amount_yen'],10000);expect(result.payload['form_fields']['rows'][0]['amount_yen'],900);
 });
 test('schema, row count, number, quantity, choice, date and unknown namespace all validate',(){
  final invalid=<Map<String,dynamic>>[];
  Map<String,dynamic> empty()=>TradeDocumentFormFields.empty().toJson();
  invalid.add(empty()..['extra']=true);invalid.add(empty()..['rows']=[]);invalid.add(empty()..['payment_day']=32);invalid.add(empty()..['cash_ratio_percent']='100.01');
  var v=empty();v['rows'][0]['quantity']='1e3';invalid.add(v);v=empty();v['rows'][0]['unit_price_yen']=-1;invalid.add(v);
  v=empty();v['payments']['advance']={'choice':'no','date':'2026-10-01','amount_yen':null};invalid.add(v);
  v=empty();v['payments']['advance']={'choice':'yes','date':'2026-02-30','amount_yen':null};invalid.add(v);
  v=empty();v['rows'][0]['amount_yen']='10';invalid.add(v);
  for(final raw in invalid){expect(()=>draft().withChanges({'form_fields':raw}),throwsFormatException);}
 });
 test('registered contact data is fixed and a historical or malformed snapshot cannot be upgraded implicitly',(){
  final changed=draft().payload['form_fields'] as Map<String,dynamic>;changed['issuer_phone']='03-0000-0000';expect(()=>draft().withChanges({'form_fields':changed}),throwsFormatException);
  expect(()=>TradeDocumentFormDraft.fromPayload(formBody()..remove('contract_terms'),allowAmountEditing:false),throwsFormatException);
  expect(()=>TradeDocumentFormDraft.fromPayload({...formBody(),'form_fields':null},allowAmountEditing:false),throwsFormatException);
 });
 test('complete original scope and body references survive all legitimate edits',(){
  final original=draft(),before=original.payload,result=original.withChanges({'work_name':'明示した新工事','notes':'保存する内容'}).payload;
  for(final key in ['issuer','counterparty','contract_terms','company_seal_snapshot','company_seal_enabled','month','total_amount_yen','tax_amount_yen']){expect(result[key],before[key]);}
  expect(original.payload['work_name'],'実際の工事');
 });
}
