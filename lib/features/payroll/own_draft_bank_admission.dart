import '../people/own_bank_account_repository.dart';

const ownDraftBankContract = 'sko.personal_payroll_own_draft_bank.v1';
const ownDraftBankContractSha256 = '126eb802f6961e43dd15577b0aee66b7d3196da8795bfc8a9cbdee8560ec24b3';
enum OwnDraftBankState { available, confirmedAbsent, unavailable }
class OwnDraftBankAdmission {
 OwnDraftBankAdmission._(this.statementId,this.statementRevision,this.personalRevision,this.state,this._bank,this._current);
 final String statementId; final int statementRevision; final int? personalRevision;
 final OwnDraftBankState state; final Map<String,dynamic>? _bank; final bool Function() _current;
 OwnDraftBankAdmission withLease(bool Function() lease) => OwnDraftBankAdmission._(statementId,statementRevision,personalRevision,state,_bank,()=>_current()&&lease());
 bool permits(String id,int? revision) => _current() && id==statementId && revision==statementRevision && state!=OwnDraftBankState.unavailable;
 Map<String,dynamic> bankFor(String id,int? revision) {
  if(!permits(id,revision))throw StateError('個人口座を確認できません。給与金額は保持しています。');
  return Map.unmodifiable(_bank??const <String,dynamic>{});
 }
 static OwnDraftBankAdmission decode(Object? raw,{required String actor,required String sid,required String statement,required int revision,required bool Function() current}) {
  Never invalid()=>throw const FormatException('個人口座の応答を確認できません。');
  const keys={'protocol_version','actor_id','session_id','statement_id','statement_revision','state','personal_revision','bank_account','reason_code'};
  if(raw is! Map || raw.length!=keys.length || raw.keys.any((k)=>!keys.contains(k)) || raw['protocol_version'] is! int || raw['protocol_version']!=1 || raw['actor_id']!=actor || raw['session_id']!=sid || raw['statement_id']!=statement || raw['statement_revision'] is! int || raw['statement_revision']!=revision)invalid();
  final version=raw['personal_revision'],bank=raw['bank_account'];
  bool validVersion(Object? value)=>value is int&&value>=0&&value<=9007199254740991;
  if(raw['state']=='unavailable'){
   if(version!=null||bank!=null||raw['reason_code']!='basis_unavailable')invalid();
   return OwnDraftBankAdmission._(statement,revision,null,OwnDraftBankState.unavailable,null,current);
  }
  if(!validVersion(version)||raw['reason_code']!=null)invalid();
  if(raw['state']=='confirmed_absent'){
   if(bank!=null)invalid();
   return OwnDraftBankAdmission._(statement,revision,version,OwnDraftBankState.confirmedAbsent,null,current);
  }
  const bankKeys={'bank_name','branch_name','account_type','account_number','account_holder'};
  if(raw['state']!='available'||version<1||bank is! Map||bank.length!=5||bank.keys.any((k)=>!bankKeys.contains(k))||bank.values.any((v)=>v is! String))invalid();
  final input=OwnBankAccountInput(bankName:bank['bank_name'],branchName:bank['branch_name'],accountType:bank['account_type'],accountNumber:bank['account_number'],accountHolder:bank['account_holder']);
  if(!input.isValid||input.bankName!=bank['bank_name']||input.branchName!=bank['branch_name']||input.accountNumber!=bank['account_number']||input.accountHolder!=bank['account_holder'])invalid();
  return OwnDraftBankAdmission._(statement,revision,version,OwnDraftBankState.available,Map.unmodifiable(Map<String,dynamic>.from(bank)),current);
 }
}
const ownDraftBankAliases={'bank_account','bank_name','銀行名','bank_branch','branch_name','支店名','bank_account_type','account_type','口座種別','bank_account_number','account_number','口座番号','bank_account_holder','account_holder','口座名義'};
Map<String,dynamic> sanitizeOwnDraftBank(Map<String,dynamic> detail) => Map<String,dynamic>.fromEntries(detail.entries.where((e)=>!ownDraftBankAliases.contains(e.key)));
