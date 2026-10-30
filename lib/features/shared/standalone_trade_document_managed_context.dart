import 'dart:convert';
import '../../domain/company_seal_snapshot.dart';
import '../../domain/partner_company_bank_account.dart';

/// Validates the dedicated managed-hub RPC receipt. It does not infer authority
/// from the client role, a same-name company, or an existing legacy loader.
Map<String,dynamic> managedTradeDocumentContext(Object? raw,{
 required String actorId,required String sessionIdentity,required String companyId,
 required String tradeCompanyId,required bool acceptance,
}){
 const requiredKeys={'context_contract_version','actor_id','session_id','company_id','trade_company_id','acceptance',
  'issuer','counterparty','template','company_seal_snapshot','company_seal_enabled','bank_backend_available'};
 const optionalKeys={'partner_company_id','counterparty_bank'};
 final uuid=RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
 Never invalid()=>throw StateError('現場管理の会社・本人・書類作成権限を確認できません。開き直してください。');
 if(raw is! Map || raw.keys.any((k)=>k is! String||!{...requiredKeys,...optionalKeys}.contains(k)) ||
  !requiredKeys.every(raw.containsKey) || raw['context_contract_version'] is! int || raw['context_contract_version']!=1 ||
  raw['actor_id']!=actorId || raw['company_id']!=companyId || raw['trade_company_id']!=tradeCompanyId || raw['acceptance']!=acceptance ||
  raw['session_id'] is! String || !uuid.hasMatch(raw['session_id'] as String) || '$actorId/${raw['session_id']}'!=sessionIdentity ||
  !uuid.hasMatch(actorId)||!uuid.hasMatch(companyId)||!uuid.hasMatch(tradeCompanyId) ||
  raw['company_seal_enabled']!=true || raw['bank_backend_available'] is! bool){invalid();}
 String text(Object? v,int max,{bool blank=true,bool multiline=false}){
  if(v is! String||v.runes.length>max||(!blank&&v.trim().isEmpty)||
   RegExp(multiline?r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]':r'[\x00-\x1f\x7f]').hasMatch(v)){invalid();}
  return v;
 }
 for(final key in ['issuer','counterparty']){
  final p=raw[key],keys={'name','address','corporate_number','representative_name','phone',if(key=='issuer')'fax'};
  if(p is! Map||p.length!=keys.length||!keys.every(p.containsKey))invalid();
  text(p['name'],240,blank:false);text(p['address'],240,multiline:true);text(p['representative_name'],80);
  text(p['phone'],40);if(key=='issuer')text(p['fax'],40);
  final number=text(p['corporate_number'],13);
  if(number.isNotEmpty&&!RegExp(r'^\d{13}$').hasMatch(number))invalid();
 }
 final template=raw['template'];
 const prose={'intro_text','acceptance_text','payment_conditions','notes','work_name','work_address','auto_generate'};
 if(template is! Map||template.keys.any((k)=>k is! String||!prose.contains(k)))invalid();
 for(final entry in template.entries){
  if(entry.key=='auto_generate'){if(entry.value is! bool)invalid();}
  else{text(entry.value,entry.key=='notes'?600:{'work_name','work_address'}.contains(entry.key)?240:400,multiline:true);}
 }
 final seal=raw['company_seal_snapshot'];
 if(seal is! Map||seal['version'] is! int||seal['company_id']!=companyId||seal['name']!=raw['issuer']['name'])invalid();
 final sealKeys=seal['version']==1?{'version','style','name','company_id'}:
  seal['version']==2?{'version','style','name','company_id','png_version_id','png_base64','png_sha256'}:<String>{};
 if(sealKeys.isEmpty||seal.length!=sealKeys.length||!sealKeys.every(seal.containsKey))invalid();
 CompanySealSnapshot.fromJson(seal);
 final partner=raw['partner_company_id'];
 if(acceptance&&(raw.containsKey('partner_company_id')||raw.containsKey('counterparty_bank')))invalid();
 if(raw.containsKey('partner_company_id')&&(partner is! String||!uuid.hasMatch(partner)))invalid();
 if(raw['bank_backend_available']==true&&(acceptance||partner==null))invalid();
 if(raw.containsKey('counterparty_bank')){
  if(raw['bank_backend_available']!=true||partner is! String||raw['counterparty_bank']==null)invalid();
  PartnerCompanyBankAccount.fromJson(raw['counterparty_bank'],companyId:companyId,partnerCompanyId:partner);
 }
 // Return a private copy; actor/SID remain receipt evidence, never editable fields.
 return Map<String,dynamic>.from(jsonDecode(jsonEncode(raw)) as Map);
}
