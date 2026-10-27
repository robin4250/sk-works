import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../../data/supabase_backend.dart';
import 'security_collector_repository.dart';

class SecurityNoticeCommand {
  SecurityNoticeCommand({required this.eventId, required this.action,
    required this.reason, required this.revision, required this.commandId});
  final String eventId, action, reason, commandId;
  final int revision;
  static String newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    final value = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0,8)}-${value.substring(8,12)}-${value.substring(12,16)}-${value.substring(16,20)}-${value.substring(20)}';
  }
}

class SecurityNoticeSnapshot {
  const SecurityNoticeSnapshot(this.events,this.capacityGaps);
  final List<Map<String,dynamic>> events;
  final int capacityGaps;
}

class SecurityNoticeRepository {
  SecurityNoticeRepository({required this.collector, required this.readRpc, required this.updateRpc});
  final SecurityCollectorRepository collector;
  final Future<dynamic> Function(String proof) readRpc;
  final Future<dynamic> Function(SecurityNoticeCommand command, String proof) updateRpc;
  static SecurityNoticeRepository? maybeCreate() {
    final collector=SecurityCollectorRepository.maybeCreate();
    if(collector==null || !SupabaseBackend.isInitialized) return null;
    final client=SupabaseBackend.client;
    return SecurityNoticeRepository(collector:collector,
      readRpc:(proof)=>client.rpc('read_security_observation_notices',params:{'p_proof':proof}),
      updateRpc:(c,proof)=>client.rpc('update_security_observation_notice',params:{
        'p_event_id':c.eventId,'p_action':c.action,'p_reason':c.reason,
        'p_expected_revision':c.revision,'p_command_id':c.commandId,'p_proof':proof}));
  }
  Future<T> _bound<T>(Future<T> Function(void Function()) work,{bool Function()? isActive}) async {
    final initial=collector.sessionKey();
    if(initial==null) throw SecurityCollectorUnavailable();
    var changed=false;
    final sub=collector.sessionChanges.listen((key){if(key!=initial || collector.sessionKey()!=initial) changed=true;},onError:(Object _){changed=true;});
    void check(){if(changed || collector.sessionKey()!=initial || isActive?.call()==false) throw SecurityCollectorUnavailable();}
    try{check();final value=await work(check);check();return value;}finally{await sub.cancel();}
  }
  Future<SecurityNoticeSnapshot> load(String password,{bool Function()? isActive}) => _bound((check) async {
    if(password.isEmpty || !await collector.available()) throw SecurityCollectorUnavailable();
    check();final proof=await collector.issueProof(password).timeout(const Duration(seconds:30));check();
    if(!RegExp(r'^[0-9a-f]{64}$').hasMatch(proof)) throw SecurityCollectorUnavailable();
    final raw=await readRpc(proof).timeout(const Duration(seconds:20));check();
    if(raw is! Map || raw['version']!=1 || raw['coverage']!='collector_observations_only' || raw['attack_confirmed']!=false || raw['capacity_gaps'] is! int || raw['capacity_gaps']<0 || raw['events'] is! List || (raw['events'] as List).length>100 || utf8.encode(jsonEncode(raw)).length>128*1024) throw const FormatException('通知情報を確認できません');
    final rows=<Map<String,dynamic>>[]; final seen=<String>{};
    const keys={'event_id','event_kind','generation','occurred_at','available_at','read_at','review_state','review_reason','revision','scope','state'};
    for(final row in raw['events'] as List){
      if(row is! Map || row.length!=keys.length || !row.keys.every(keys.contains) || row['event_id'] is! String || !RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(row['event_id']) || !seen.add(row['event_id']) ||
        !const {'current_lure_touched','retired_lure_touched'}.contains(row['event_kind']) || row['generation'] is! int || row['generation']<1 || row['generation']>1000000 || row['revision'] is! int || row['revision']<1 || row['scope']!='decoy_generation_only' || row['state']!='observed' || !const {'unreviewed','investigating','false_positive','resolved'}.contains(row['review_state']) ||
        row['occurred_at'] is! String || DateTime.tryParse(row['occurred_at'])==null || row['available_at'] is! String || DateTime.tryParse(row['available_at'])==null || (row['read_at']!=null && (row['read_at'] is! String || DateTime.tryParse(row['read_at'])==null)) || (row['review_reason']!=null && (row['review_reason'] is! String || (row['review_reason'] as String).length>500))) { throw const FormatException('通知情報を確認できません'); }
      rows.add(Map<String,dynamic>.unmodifiable(Map<String,dynamic>.from(row)));
    }
    return SecurityNoticeSnapshot(List.unmodifiable(rows),raw['capacity_gaps']);
  },isActive:isActive);
  Future<void> update(SecurityNoticeCommand c,String password,{bool Function()? isActive}) => _bound((check) async {
    if(password.isEmpty || !await collector.available()) throw SecurityCollectorUnavailable();
    check();final proof=await collector.issueProof(password).timeout(const Duration(seconds:30));check();
    if(!RegExp(r'^[0-9a-f]{64}$').hasMatch(proof)) throw SecurityCollectorUnavailable();
    final raw=await updateRpc(c,proof).timeout(const Duration(seconds:20));check();
    if(raw is! Map || raw['event_id']!=c.eventId || raw['revision']!=c.revision+1 || raw['replayed'] is! bool) throw const FormatException('対応結果を確認できません');
  },isActive:isActive);
}
