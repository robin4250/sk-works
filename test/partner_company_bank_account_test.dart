import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/domain/partner_company_bank_account.dart';
import 'package:sk_works/features/shared/trade_document_attachment.dart';
import 'package:sk_works/features/payroll/payment_order_resolver.dart';

const company='10000000-0000-4000-8000-000000000001',partner='10000000-0000-4000-8000-000000000002';
Map<String,dynamic> bank()=>{'schema':1,'company_id':company,'partner_company_id':partner,'bank_version':2,
 'bank_name':'検証銀行','branch_name':'本店','account_type':'普通','account_number':'0000123','account_holder':'テストカイシャ'};
Map<String,dynamic> order()=>{'version':1,'kind':'order','month':'2026-10','issue_date':'2026-09-15','period_start':'2026-10-01','period_end':'2026-10-31',
 'issuer':{'name':'発注会社'},'counterparty':{'name':'受注会社'},'total_amount_yen':110000,'tax_amount_yen':10000,
 'company_seal_snapshot':{'version':1,'style':'legacy','name':'発注会社'},'company_seal_enabled':false};
void main(){
 test('supplier bank snapshot preserves 7-digit leading zero and company/partner/version',(){
  final source=bank();final account=PartnerCompanyBankAccount.fromJson(source,companyId:company,partnerCompanyId:partner);
  expect(account.accountNumber,'0000123');expect(account.toJson(),source);expect(account.display,contains('0000123'));
  source['account_number']='9999999';expect(account.accountNumber,'0000123');
 });
 for(final entry in {'account_number':'123','account_type':'unknown','bank_name':'x\ny','bank_version':0,'partner_company_id':'not-worker-or-partner','schema':2}.entries){
  test('snapshot rejects invalid ${entry.key}',(){expect(()=>PartnerCompanyBankAccount.fromJson({...bank(),entry.key:entry.value}),throwsFormatException);});
 }
 test('snapshot rejects foreign company or partner and unknown fields',(){
  expect(()=>PartnerCompanyBankAccount.fromJson(bank(),companyId:partner),throwsFormatException);
  expect(()=>PartnerCompanyBankAccount.fromJson(bank(),partnerCompanyId:company),throwsFormatException);
  expect(()=>PartnerCompanyBankAccount.fromJson({...bank(),'worker_id':partner}),throwsFormatException);
 });
 test('new monthly order copies authoritative optional bank but saved/locked originals remain unchanged',(){
  final defaults={...order(),'counterparty_bank':bank()};final workspace={'source_locked':false,'source_blocked':false,'source_changed':false,'attachment':null,'defaults':defaults};
  final generated=PaymentOrderResolver.resolve(workspace)!;expect(generated.payload['counterparty_bank'],bank());
  final old=TradeDocumentAttachment.fromJson({'version':3,'payload':order()});
  final saved=PaymentOrderResolver.resolve({...workspace,'attachment':{'version':old.version,'payload':old.payload},'source_locked':true})!;
  expect(saved.version,3);expect(saved.payload.containsKey('counterparty_bank'),false);
  expect(PaymentOrderResolver.resolve({...workspace,'source_locked':true}),isNull);
  expect(()=>PaymentOrderResolver.resolve({...workspace,'source_changed':true}),throwsStateError);
 });
 test('bank is not silently added to acceptance or invalid saved payload',(){
  final oldAcceptance={...order(),'kind':'acceptance','counterparty_bank':{'legacy':'ignored'}};
  expect(TradeDocumentAttachment.fromJson({'version':1,'payload':oldAcceptance}).payload,oldAcceptance);
  expect(TradeDocumentAttachment.fromJson({'version':1,'payload':{...order(),'counterparty_bank':null}}).payload['counterparty_bank'],isNull);
  expect(()=>TradeDocumentAttachment.fromJson({'version':1,'payload':{...order(),'counterparty_bank':{...bank(),'account_number':'bad'}}}),throwsFormatException);
 });
}
