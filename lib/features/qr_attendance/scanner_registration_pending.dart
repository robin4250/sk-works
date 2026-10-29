import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'scanner_registration_key.dart';
import 'scanner_registration_transport.dart';

String scannerRequestId() {
 final random=Random.secure(),b=List.generate(16,(_)=>0);for(var i=0;i<b.length;i++){b[i]=random.nextInt(256);}b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;
 final h=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}
bool _same(Object? a,Object? b) {
 if(a is Map && b is Map) return a.length==b.length && a.keys.every((k)=>b.containsKey(k) && _same(a[k],b[k]));
 if(a is List && b is List) return a.length==b.length && List.generate(a.length,(i)=>i).every((i)=>_same(a[i],b[i]));
 return a==b;
}
StateError _blocked()=>StateError('保存された元の登録手続きを確認できません。新規登録を繰り返さないでください。');
class ScannerRegistrationPending {
 ScannerRegistrationPending._(this.data);
 final Map<String,dynamic> data;
 static final _uuid=RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
 factory ScannerRegistrationPending.parse(Object? raw,ScannerRegistrationSession owner,String company) {
  const fields={'schema','actor','company','session','device','handle','nonce','version','stage','publicKeyHex','challenge','challengeRequestId','proofRequestIds','completionRequestId','registrationEventId'};
  if(raw is! Map || raw.keys.toSet().difference(fields).isNotEmpty || raw.length!=fields.length) { throw _blocked(); }
  final p=Map<String,dynamic>.from(raw);
  if(p['schema']!=1 || p['actor']!=owner.actor || p['company']!=company || p['session']!=owner.sid ||
      p['version'] is! int || p['version']<0 || p['version']>9007199254740991 ||
      !['device','nonce'].every((k)=>p[k] is String && _uuid.hasMatch(p[k] as String)) ||
      p['handle'] is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(p['handle'] as String) ||
      !['key_pending','key_ready','challenge_sent','challenge_ready','proof_sent','proof_rejected','proof_delivered','proof_lost','completion_sent','confirmed'].contains(p['stage']) ||
      p['proofRequestIds'] is! List || (p['proofRequestIds'] as List).length>5 ||
      !(p['proofRequestIds'] as List).every((id)=>id is String && _uuid.hasMatch(id))) { throw _blocked(); }
  final expectedHandle=sha256.convert(utf8.encode('sko.qr.scanner.custody.v1\n${owner.actor}\n$company\n${p['device']}')).toString();
  if(p['handle']!=expectedHandle || (p['proofRequestIds'] as List).toSet().length!=(p['proofRequestIds'] as List).length) { throw _blocked(); }
  if(p['stage']=='key_pending') { if(p['publicKeyHex']!=null) { throw _blocked(); } }
  else if(p['publicKeyHex'] is! String || !RegExp(r'^302a300506032b6570032100[0-9a-f]{64}$').hasMatch(p['publicKeyHex'] as String)) { throw _blocked(); }
  for(final field in ['challengeRequestId','completionRequestId']){if(p[field]!=null && (p[field] is! String || !_uuid.hasMatch(p[field] as String))) { throw _blocked(); }}
  if(p['challenge']!=null){
   final c=p['challenge'];if(c is! Map || c.length!=10 || c['actor']!=owner.actor || c['session']!=owner.sid || c['company']!=company || c['device']!=p['device'] || c['keyHex']!=p['publicKeyHex'] ||
       !['id','nonce'].every((k)=>c[k] is String && _uuid.hasMatch(c[k] as String)) ||
       !['createdMs','expiresMs','databaseNowMs'].every((k)=>c[k] is int && (c[k] as int).abs()<=9007199254740991) ||
       c['expiresMs']<=c['createdMs'] || c['expiresMs']-c['createdMs']>90000 || c['databaseNowMs']<c['createdMs'] || c['databaseNowMs']>=c['expiresMs']) { throw _blocked(); }
   p['challenge']=Map<String,dynamic>.unmodifiable(Map<String,dynamic>.from(c));
  }
  final stage=p['stage'];
  if((p['challengeRequestId']!=null)!=!['key_pending','key_ready'].contains(stage) ||
      (p['challenge']!=null)!=!['key_pending','key_ready','challenge_sent'].contains(stage) ||
      (p['proofRequestIds'] as List).isEmpty!=['key_pending','key_ready','challenge_sent','challenge_ready'].contains(stage) ||
      (p['completionRequestId']!=null)!=['completion_sent','confirmed'].contains(stage) ||
      (p['registrationEventId']!=null)!=(stage=='confirmed')) { throw _blocked(); }
  if(p['registrationEventId']!=null && (p['registrationEventId'] is! String || !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(p['registrationEventId'] as String) || BigInt.parse(p['registrationEventId'] as String)>BigInt.parse('9223372036854775807'))) { throw _blocked(); }
  p['proofRequestIds']=List<String>.unmodifiable((p['proofRequestIds'] as List).cast<String>());
  return ScannerRegistrationPending._(Map<String,dynamic>.unmodifiable(p));
 }
 String get stage=>data['stage'] as String;
 int get version=>data['version'] as int;
 Map<String,dynamic>? get challenge=>data['challenge'] as Map<String,dynamic>?;
 ScannerRegistrationKey get key=>ScannerRegistrationKey(actor:data['actor'] as String,company:data['company'] as String,device:data['device'] as String,handle:data['handle'] as String,publicKeyHex:data['publicKeyHex'] as String);
 bool sameImmutable(ScannerRegistrationPending other)=>['actor','company','session','device','handle','nonce'].every((k)=>data[k]==other.data[k]);
}

/// Native process-serialized write-ahead item; no SharedPreferences fallback.
class ScannerRegistrationJournal {
 ScannerRegistrationJournal({this.enabled=false,this.channel=const MethodChannel('com.skworks.sko/qr_scanner_pending')});
 final bool enabled;
 final MethodChannel channel;
 Future<Object?> _call(ScannerRegistrationSession owner,String company,String method,Map<String,dynamic> extra) async {
  if(!enabled || !ScannerRegistrationPending._uuid.hasMatch(company)) { throw _blocked(); }
  await owner.verify();final requestId=scannerRequestId();
  try {
   final value=await owner.wait(()=>channel.invokeMethod<Object?>(method,{'requestId':requestId,'actor':owner.actor,'company':company,'session':owner.sid,...extra}),const Duration(seconds:95));owner.live();return value;
  } catch (_){unawaited(channel.invokeMethod<void>('cancel',{'requestId':requestId}).catchError((Object _){}));throw _blocked();}
 }
 Future<ScannerRegistrationPending?> read(ScannerRegistrationSession owner,String company) async {
  final value=await _call(owner,company,'read',{});
  if(value is Map && value.length==1 && value['status']=='absent') return null;
  if(value is! Map || value.length!=2 || value['status']!='found') { throw _blocked(); }
  return ScannerRegistrationPending.parse(value['pending'],owner,company);
 }
 Future<ScannerRegistrationPending> createExplicitNewLogicalDevice(ScannerRegistrationSession owner,String company) async {
  final value=await _call(owner,company,'createNewLogicalDeviceIntent',{});
  final pending=ScannerRegistrationPending.parse(value,owner,company);
  if(pending.stage!='key_pending' || pending.version!=0) { throw _blocked(); }return pending;
 }
 Future<ScannerRegistrationPending> advance(ScannerRegistrationSession owner,ScannerRegistrationPending old,String next,Map<String,dynamic> patch) async {
  final value=await _call(owner,old.data['company'] as String,'advance',{'expectedVersion':old.version,'nextStage':next,'patch':patch});
  final pending=ScannerRegistrationPending.parse(value,owner,old.data['company'] as String);
  if(!old.sameImmutable(pending) || pending.version!=old.version+1 || pending.stage!=next) { throw _blocked(); }
  final expected=Map<String,dynamic>.from(old.data)..['version']=old.version+1..['stage']=next;
  for(final entry in patch.entries){if(entry.key=='proofRequestId'){expected['proofRequestIds']=[...(old.data['proofRequestIds'] as List),entry.value];}else{expected[entry.key]=entry.value;}}
  if(!_same(expected,pending.data)) { throw _blocked(); }return pending;
 }
}
