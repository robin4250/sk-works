import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

const companyCommonRateLabels = <String, String>{
 'overtime_hour_rate_yen': '残業単価（1時間・円）',
 'early_hour_rate_yen': '早出単価（1時間・円）',
 'night_hour_rate_yen': '夜勤単価（1時間・円）',
 'holiday_day_rate_yen': '休日出勤単価（1日・円）',
};
String commonRatesUuid(String value) {
 if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(value)) throw const FormatException('会社設定の対象を確認できません');
 return value.toLowerCase();
}
Map<String, dynamic> commonRatesObject(Object? value) {
 if (value is! Map || value.keys.any((key) => key is! String)) throw const FormatException('単価設定を確認できません');
 return Map<String, dynamic>.from(value);
}
bool commonRatesEqual(Object? a, Object? b) {
 if (a is Map && b is Map) return a.length == b.length && a.keys.every((key) => b.containsKey(key) && commonRatesEqual(a[key], b[key]));
 if (a is List && b is List) return a.length == b.length && List.generate(a.length, (i) => i).every((i) => commonRatesEqual(a[i], b[i]));
 return a == b;
}
Map<String, int> _rates(Object? value) {
 final rates = commonRatesObject(value);
 if (rates.length != companyCommonRateLabels.length || !rates.keys.every(companyCommonRateLabels.containsKey) || rates.values.any((x) => x is! int || x < 0 || x > 2147483647)) throw const FormatException('4つの単価を0〜2147483647の整数で確認してください');
 return Map<String, int>.unmodifiable(rates.cast<String, int>());
}
class CompanyCommonRatesState {
 const CompanyCommonRatesState._({required this.companyId, required this.canEdit, required this.version, required this.rates});
 final String companyId;
 final bool canEdit;
 final int version;
 final Map<String, int> rates;
 factory CompanyCommonRatesState.parse(Object? raw, String companyId, {bool commit = false}) {
  final value = commonRatesObject(raw);
  final keys = {'contract_version','company_id','can_edit','version','rates', if (commit) ...['request_id','committed_version','id_map']};
  if (value.length != keys.length || !value.keys.every(keys.contains) || value['contract_version'] != 1 || value['company_id'] != commonRatesUuid(companyId) || value['can_edit'] is! bool || value['version'] is! int || value['version'] < 0 || value['version'] > 9007199254740991) throw const FormatException('単価設定の応答を確認できません');
  return CompanyCommonRatesState._(companyId: commonRatesUuid(companyId), canEdit: value['can_edit'], version: value['version'], rates: _rates(value['rates']));
 }
 bool sameSource(CompanyCommonRatesState other) => companyId == other.companyId && version == other.version && commonRatesEqual(rates, other.rates);
}
class CompanyCommonRatesRequest {
 CompanyCommonRatesRequest({required String companyId, required String actorId, required String requestId, required this.expectedVersion, required Map<String, int> expectedRates, required Map<String, int> rates}) : companyId = commonRatesUuid(companyId), actorId = commonRatesUuid(actorId), requestId = commonRatesUuid(requestId), expectedRates = _rates(expectedRates), rates = _rates(rates) {
  if (expectedVersion < 0 || expectedVersion > 9007199254740990) throw const FormatException('単価設定の版を確認できません');
 }
 final String companyId, actorId, requestId;
 final int expectedVersion;
 final Map<String, int> expectedRates, rates;
 Map<String, dynamic> get payload => {'operation':'rates','expected_version':expectedVersion,'expected_rates':expectedRates,'rates':rates};
 Map<String, dynamic> toJson() => {'journal_version':1,'company_id':companyId,'actor_id':actorId,'request_id':requestId,'request_payload':payload};
 factory CompanyCommonRatesRequest.parse(Object? raw, String companyId, String actorId) {
  final value = commonRatesObject(raw);
  const keys = {'journal_version','company_id','actor_id','request_id','request_payload'};
  if (value.length != keys.length || !value.keys.every(keys.contains) || value['journal_version'] != 1 || value['company_id'] != commonRatesUuid(companyId) || value['actor_id'] != commonRatesUuid(actorId) || value['request_id'] is! String) throw const FormatException('単価の保存確認情報の対象が違います');
  final p = commonRatesObject(value['request_payload']);
  const payloadKeys = {'operation','expected_version','expected_rates','rates'};
  if (p.length != payloadKeys.length || !p.keys.every(payloadKeys.contains) || p['operation'] != 'rates' || p['expected_version'] is! int) throw const FormatException('単価の保存確認情報を確認できません');
  return CompanyCommonRatesRequest(companyId:companyId,actorId:actorId,requestId:value['request_id'],expectedVersion:p['expected_version'],expectedRates:_rates(p['expected_rates']),rates:_rates(p['rates']));
 }
 CompanyCommonRatesState validateCommit(Object? raw) {
  final value = commonRatesObject(raw);
  final state = CompanyCommonRatesState.parse(value,companyId,commit:true);
  if (value['request_id'] != requestId || value['committed_version'] != expectedVersion + 1 || state.version != expectedVersion + 1 || value['id_map'] is! List || (value['id_map'] as List).isNotEmpty || !commonRatesEqual(state.rates,rates)) throw const FormatException('単価の保存結果が一致しません');
  return state;
 }
 CompanyCommonRatesState? validateReceipt(Object? raw) {
  final value = commonRatesObject(raw);
  final base = {'contract_version','company_id','request_id','found'};
  if (value['contract_version'] != 1 || value['company_id'] != companyId || value['request_id'] != requestId || value['found'] is! bool) throw const FormatException('単価の保存確認対象が一致しません');
  if (value['found'] == false) { if (value.length != base.length || !value.keys.every(base.contains)) throw const FormatException('単価の保存確認形式が違います'); return null; }
  final keys = {...base,'actor_id','operation','payroll_type','expected_version','request_payload','committed_version','result'};
  if (value.length != keys.length || !value.keys.every(keys.contains) || value['actor_id'] != actorId || value['operation'] != 'rates' || value['payroll_type'] != null || value['expected_version'] != expectedVersion || value['committed_version'] != expectedVersion + 1 || !commonRatesEqual(value['request_payload'],payload)) throw const FormatException('単価の保存確認操作が一致しません');
  return validateCommit(value['result']);
 }
}
class CompanyCommonRatesUnavailable implements Exception { const CompanyCommonRatesUnavailable(); }
abstract class CompanyCommonRatesRepository {
 String? get actorId;
 Stream<String?> get actorChanges;
 Future<CompanyCommonRatesState> read(String companyId);
 Future<CompanyCommonRatesState> save(CompanyCommonRatesRequest request);
 Future<CompanyCommonRatesState?> receipt(CompanyCommonRatesRequest request);
}
class SupabaseCompanyCommonRatesRepository implements CompanyCommonRatesRepository {
 SupabaseCompanyCommonRatesRepository(this.client);
 final SupabaseClient client;
 static CompanyCommonRatesRepository? maybeCreate() => SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentUser != null ? SupabaseCompanyCommonRatesRepository(SupabaseBackend.client) : null;
 @override String? get actorId => client.auth.currentUser?.id;
 @override Stream<String?> get actorChanges => client.auth.onAuthStateChange.map((event) => event.session?.user.id);
 Future<dynamic> _call(String name, Map<String,dynamic> params,{String? expectedActor}) async {
  final session = client.auth.currentSession;
  if (session == null || expectedActor != null && session.user.id != expectedActor) throw StateError('ログイン状態が変わりました');
  try {
   final result = await client.rpc(name,params:params).setHeader('Authorization','Bearer ${session.accessToken}').timeout(const Duration(seconds:30));
   if (actorId != session.user.id) throw StateError('ログイン状態が変わりました');
   return result;
  } on PostgrestException catch (error) { if (error.code == 'PGRST202') throw const CompanyCommonRatesUnavailable(); rethrow; }
 }
 @override Future<CompanyCommonRatesState> read(String companyId) async => CompanyCommonRatesState.parse(await _call('read_company_common_rate_settings',{'p_company_id':commonRatesUuid(companyId)}),companyId);
 @override Future<CompanyCommonRatesState> save(CompanyCommonRatesRequest request) async => request.validateCommit(await _call('save_company_common_rate_settings',{'p_company_id':request.companyId,'p_expected_version':request.expectedVersion,'p_expected_rates':request.expectedRates,'p_rates':request.rates,'p_request_id':request.requestId},expectedActor:request.actorId));
 @override Future<CompanyCommonRatesState?> receipt(CompanyCommonRatesRequest request) async => request.validateReceipt(await _call('read_company_common_allowance_request',{'p_company_id':request.companyId,'p_request_id':request.requestId},expectedActor:request.actorId));
}
