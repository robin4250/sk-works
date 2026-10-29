import 'dart:convert';
import 'partner_company_bank_account.dart';

/// Preserve saved user/immutable snapshot fields during an explicit source
/// revision review. Defaults can never upgrade legacy absence or switch banks.
Map<String,dynamic> preserveSavedTradeDocumentFields({required Map<String,dynamic> payload,
 required Map<String,dynamic> workspace,required String subjectKind,required String subjectId}) {
 final result=Map<String,dynamic>.from(jsonDecode(jsonEncode(payload)) as Map),attachment=workspace['attachment'];
 if(attachment is! Map)return result;
 final raw=attachment['payload'];if(raw is! Map)throw StateError('保存済み書類を確認できません。');
 final saved=Map<String,dynamic>.from(raw);
 if(subjectKind=='payment_certificate'&&saved['counterparty_bank']!=null){
  final company=workspace['company_id'];if(company is! String)throw StateError('保存した振込先の会社を確認できません。');
  final bank=PartnerCompanyBankAccount.fromJson(saved['counterparty_bank'],companyId:company);
  final binding=workspace['canonical_parent_binding'];
  if(binding is! Map||binding['parent_id']!=subjectId||binding['company_id']!=company||binding['partner_company_id']!=bank.partnerCompanyId){
   throw StateError('保存した振込先と現在の受注者の対応を確認できません。旧書類は保持しています。新しい正式書類として確認してください。');
  }
 }
 for(final key in ['contract_terms','counterparty_bank','form_fields']){
  if(saved.containsKey(key))result[key]=jsonDecode(jsonEncode(saved[key]));else result.remove(key);
 }
 return result;
}
