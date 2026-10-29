/// A company-scoped supplier bank snapshot. Never a worker's personal account.
class PartnerCompanyBankAccount {
  PartnerCompanyBankAccount({required this.companyId,required this.partnerCompanyId,
    required this.bankVersion,required this.bankName,required this.branchName,
    required this.accountType,required this.accountNumber,required this.accountHolder}) {
    if(!_uuid.hasMatch(companyId) || !_uuid.hasMatch(partnerCompanyId) ||
      bankVersion<1 || bankVersion>2147483647 ||
      !_text(bankName,100) || !_text(branchName,100) || !_text(accountHolder,120) ||
      !const ['普通','当座','貯蓄'].contains(accountType) || !RegExp(r'^[0-9]{7}$').hasMatch(accountNumber)) {
      throw const FormatException('協力会社の銀行口座情報を確認してください。口座番号は半角7桁です。');
    }
  }
  static final _uuid=RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
  static bool _text(String value,int max)=>value.trim().isNotEmpty && value==value.trim() && value.runes.length<=max && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
  final String companyId,partnerCompanyId,bankName,branchName,accountType,accountNumber,accountHolder;
  final int bankVersion;
  static const fields={'schema','company_id','partner_company_id','bank_version','bank_name','branch_name','account_type','account_number','account_holder'};
  factory PartnerCompanyBankAccount.fromJson(Object? raw,{String? companyId,String? partnerCompanyId}) {
    if(raw is! Map || raw.length!=fields.length || raw.keys.toSet().difference(fields).isNotEmpty || raw['schema']!=1 ||
      raw['bank_version'] is! int || !['company_id','partner_company_id','bank_name','branch_name','account_type','account_number','account_holder'].every((key)=>raw[key] is String) ||
      (companyId!=null && raw['company_id']!=companyId) || (partnerCompanyId!=null && raw['partner_company_id']!=partnerCompanyId)) {
      throw const FormatException('協力会社の振込先の所属・保存版を確認できません。');
    }
    return PartnerCompanyBankAccount(companyId:raw['company_id'] as String,partnerCompanyId:raw['partner_company_id'] as String,
      bankVersion:raw['bank_version'] as int,bankName:raw['bank_name'] as String,branchName:raw['branch_name'] as String,
      accountType:raw['account_type'] as String,accountNumber:raw['account_number'] as String,accountHolder:raw['account_holder'] as String);
  }
  Map<String,dynamic> toJson()=>{'schema':1,'company_id':companyId,'partner_company_id':partnerCompanyId,'bank_version':bankVersion,
    'bank_name':bankName,'branch_name':branchName,'account_type':accountType,'account_number':accountNumber,'account_holder':accountHolder};
  Map<String,String> get bankFields=>{'bank_name':bankName,'branch_name':branchName,'account_type':accountType,'account_number':accountNumber,'account_holder':accountHolder};
  String get display=>'銀行：$bankName　支店：$branchName\n種別：$accountType　口座番号：$accountNumber\n口座名義：$accountHolder';
}
