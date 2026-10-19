import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_backend.dart';

class CommonPayrollPublicationState {
  const CommonPayrollPublicationState({required this.companyId, required this.canEdit,
    required this.timelineVersion, required this.commonVersion, required this.commonSourceJson, required this.entries});
  final String companyId;
  final bool canEdit;
  final int timelineVersion, commonVersion;
  final String commonSourceJson;
  final List<Map<String, dynamic>> entries;
  factory CommonPayrollPublicationState.parse(Object? raw, String companyId) {
    bool version(Object? x) => x is int && x >= 0 && x <= 9007199254740991;
    if (raw is! Map || raw['contract_version'] != 1 || raw['company_id'] != companyId ||
        raw['can_edit'] is! bool || !version(raw['timeline_version']) || !version(raw['common_version']) ||
        raw['common_source'] is! Map || raw['entries'] is! List) throw StateError('Payroll publication response unavailable');
    final entries = <Map<String, dynamic>>[];
    for (final entry in raw['entries'] as List) {
      if (entry is! Map || !version(entry['version']) ||
          !['daily','hourly','monthly'].contains(entry['payroll_type']) || entry['starts_on'] is! String ||
          !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(entry['starts_on'] as String) || entry['request_id'] is! String) {
        throw StateError('Payroll publication entry unavailable');
      }
      entries.add(Map.unmodifiable(Map<String, dynamic>.from(entry)));
    }
    return CommonPayrollPublicationState(companyId: companyId, canEdit: raw['can_edit'] as bool,
      timelineVersion: raw['timeline_version'] as int, commonVersion: raw['common_version'] as int,
      commonSourceJson: jsonEncode(raw['common_source']), entries: List.unmodifiable(entries));
  }
}
class CommonPayrollPublicationRequest {
  CommonPayrollPublicationRequest(this.state, this.payrollType, this.startsOn, {String? requestId}) : requestId = requestId ?? _newId();
  final CommonPayrollPublicationState state;
  final String payrollType, startsOn, requestId;
  static String _newId() {
    final random=Random.secure();final bytes=List.generate(16,(_)=>random.nextInt(256));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    final h=bytes.map((b)=>b.toRadixString(16).padLeft(2,'0')).join();return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }
  Map<String,dynamic> get params => {'p_company_id':state.companyId,'p_payroll_type':payrollType,'p_starts_on':startsOn,
    'p_common_version':state.commonVersion,'p_common_source':jsonDecode(state.commonSourceJson),
    'p_timeline_version':state.timelineVersion,'p_request_id':requestId};
}
abstract interface class CommonPayrollPublicationRepository {
  String? get sessionKey;
  Stream<String?> get sessionChanges;
  Future<CommonPayrollPublicationState> read(String companyId);
  Future<CommonPayrollPublicationState> publish(CommonPayrollPublicationRequest request);
}
class SupabaseCommonPayrollPublicationRepository implements CommonPayrollPublicationRepository {
  SupabaseCommonPayrollPublicationRepository(this._client);
  final SupabaseClient _client;
  static SupabaseCommonPayrollPublicationRepository? maybeCreate() => SupabaseBackend.isInitialized && SupabaseBackend.client.auth.currentSession != null
      ? SupabaseCommonPayrollPublicationRepository(SupabaseBackend.client) : null;
  @override String? get sessionKey => _client.auth.currentSession?.accessToken;
  @override Stream<String?> get sessionChanges => _client.auth.onAuthStateChange.map((e)=>e.session?.accessToken);
  Future<Object?> _call(String name, Map<String,dynamic> args) async {
    final token=sessionKey;final actor=_client.auth.currentUser?.id;if(token==null || actor==null) throw StateError('Session unavailable');
    var revoked=false;
    final subscription=_client.auth.onAuthStateChange.listen((e){if(e.session?.accessToken!=token || e.session?.user.id!=actor) revoked=true;},onError:(Object _){revoked=true;});
    try {
      final result=await _client.rpc(name,params:args).setHeader('Authorization','Bearer $token');
      if(revoked || sessionKey!=token || _client.auth.currentUser?.id!=actor) throw StateError('Session changed');
      return result;
    } finally {await subscription.cancel();}
  }
  @override Future<CommonPayrollPublicationState> read(String companyId) async => CommonPayrollPublicationState.parse(
    await _call('read_company_common_payroll_publications',{'p_company_id':companyId}),companyId);
  @override Future<CommonPayrollPublicationState> publish(CommonPayrollPublicationRequest request) async {
    if(!request.state.canEdit || !['daily','hourly','monthly'].contains(request.payrollType) ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])-01$').hasMatch(request.startsOn)) throw StateError('Payroll publication unavailable');
    final raw=await _call('publish_company_common_payroll',request.params);
    if(raw is! Map || raw['contract_version']!=1 || raw['company_id']!=request.state.companyId ||
        raw['request_id']!=request.requestId || raw['payroll_type']!=request.payrollType || raw['starts_on']!=request.startsOn ||
        raw['publication_version']!=request.state.timelineVersion+1) throw StateError('Payroll publication receipt unavailable');
    final result=CommonPayrollPublicationState.parse(raw['timeline'],request.state.companyId);
    if(result.timelineVersion!=raw['publication_version']) throw StateError('Payroll publication receipt differs');
    return result;
  }
}
