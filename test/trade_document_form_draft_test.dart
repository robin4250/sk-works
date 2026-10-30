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
 for(final kind in ['order','acceptance']) {
  test('new $kind receives agreed editable defaults with no invented rate or amount',(){
   final source=formBody()..['kind']=kind;
   final before=jsonEncode(source);
   final value=TradeDocumentFormDraft.fromPayload(source,allowAmountEditing:false,
    initializeDefaults:true,initializeExtendedFields:true);
   final p=value.payload,fields=p['form_fields'];
   expect(fields['schema'],2);expect(fields['work_content'],'とび工事');
   expect(fields['amount_description'],'下記「施工単価内訳書」による');
   expect(fields['progress_cutoff_day'],'month_end');expect(fields['invoice_cutoff_day'],10);
   expect(fields['cash_ratio_percent'],'100');expect(fields['payment_month_offset'],2);expect(fields['payment_day'],5);
   expect(fields['supplies'],'仮設材他');expect(p['notes'],tradeDocumentDefaultNotes);
   for(final key in ['advance','partial','completion']) {expect(fields['payments'][key],{'choice':'no','date':null,'amount_yen':null});}
   expect(fields['rows'][0],{'item':'とび工　安全施設・足場組立解体作業（一般作業員）','quantity':'1','unit':'人日','unit_price_yen':null,'amount_yen':null,'note':''});
   expect((fields['rows'] as List).skip(1).every((row)=>row['item']==''),isTrue);
   expect(p['total_amount_yen'],110000);expect(p['tax_amount_yen'],10000);expect(jsonEncode(source),before);
   final changed=Map<String,dynamic>.from(fields as Map)..['progress_cutoff_day']=31;
   expect(value.withChanges({'form_fields':changed}).payload['form_fields']['progress_cutoff_day'],31);
   expect(tradeDocumentClosingDay('month_end'),'末日');expect(tradeDocumentClosingDay(31),'31');
   final reopened=TradeDocumentFormDraft.fromPayload(p,allowAmountEditing:false,initializeDefaults:true,initializeExtendedFields:true);
   expect(reopened.payload,p);
  });
 }
 test('saved explicit blank form fields and notes are never replaced by new defaults',(){
  final source=formBody()..['form_fields']=TradeDocumentFormFields.empty().toJson();
  final before=jsonEncode(source);
  final reopened=TradeDocumentFormDraft.fromPayload(source,allowAmountEditing:false,initializeDefaults:true,initializeExtendedFields:true);
  expect(jsonEncode(reopened.payload),before);
 });
 test('historical missing form fields and explicit blank notes stay blank without new-document opt-in',(){
  final source=formBody();
  final p=TradeDocumentFormDraft.fromPayload(source,allowAmountEditing:false,initializeExtendedFields:true).payload;
  expect(p['notes'],'');expect(p['form_fields'],TradeDocumentFormFields.empty().toJson());
 });
 test('v2 schema only allows exact month-end sentinel and never aliases day 31',(){
  final fields=TradeDocumentFormDraft.fromPayload(formBody(),allowAmountEditing:false,initializeDefaults:true,initializeExtendedFields:true).payload['form_fields'] as Map<String,dynamic>;
  for(final bad in ['末日','31','monthEnd',0,32]) {expect(()=>TradeDocumentFormFields.fromJson({...fields,'progress_cutoff_day':bad}),throwsFormatException);}
  expect(()=>TradeDocumentFormFields.fromJson({...fields,'invoice_cutoff_day':'month_end'}),throwsFormatException);
 });
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
