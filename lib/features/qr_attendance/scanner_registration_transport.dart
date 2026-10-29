import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'scanner_registration_key.dart';

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
StateError _unavailable() => StateError('登録結果を確認できません。元の手続きを照合してください。');

/// Memory-only exact owner. It is never serialized in the pending journal.
class ScannerRegistrationSession with WidgetsBindingObserver {
  ScannerRegistrationSession(this.client) {
    final captured = client.auth.currentSession;
    if(captured == null || captured.isExpired || captured.user.isAnonymous) { throw _unavailable(); }
    actor = captured.user.id; token = captured.accessToken;
    try {
      final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
      sid = claims['session_id'] as String;
      if(claims['sub'] != actor || !_uuid.hasMatch(actor) || !_uuid.hasMatch(sid)) { throw _unavailable(); }
    } catch (_) { throw _unavailable(); }
    var first = true;
    _subscription = client.auth.onAuthStateChange.listen((event) {
      final replay = first && identical(event.session,captured) &&
          [AuthChangeEvent.initialSession,AuthChangeEvent.signedIn,AuthChangeEvent.tokenRefreshed].contains(event.event);
      first = false; if(!replay) invalidate();
    },onError:(Object _) => invalidate(),onDone:invalidate);
    WidgetsBinding.instance.addObserver(this);
    live();
  }
  final SupabaseClient client;
  late final String actor, token, sid;
  StreamSubscription<AuthState>? _subscription;
  final _invalidated = Completer<void>();
  bool _invalid = false;
  Future<void> get invalidated=>_invalidated.future;
  void invalidate() { _invalid=true;if(!_invalidated.isCompleted) _invalidated.complete(); }
  void live() {
    if(_invalid || client.auth.currentSession?.user.id != actor || client.auth.currentSession?.accessToken != token ||
        client.auth.currentSession?.isExpired != false ||
        [AppLifecycleState.inactive,AppLifecycleState.paused,AppLifecycleState.hidden,AppLifecycleState.detached].contains(WidgetsBinding.instance.lifecycleState)) { throw _unavailable(); }
  }
  Future<T> wait<T>(Future<T> Function() work,Duration budget) async {
    live();final clock=Stopwatch()..start();
    final result=await Future.any<T>([Future<T>.sync(work),_invalidated.future.then<T>((_)=>throw _unavailable())]).timeout(budget);
    live();if(clock.elapsed>=budget) { throw _unavailable(); }return result;
  }
  Future<void> verify() async {
    final value=await wait(()=>client.auth.getUser(token),const Duration(seconds:5));
    if(value.user?.id != actor || value.user?.isAnonymous != false) { throw _unavailable(); }live();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) { if(state!=AppLifecycleState.resumed) invalidate(); }
  Future<void> dispose() async { invalidate();WidgetsBinding.instance.removeObserver(this);await _subscription?.cancel(); }
}

class ScannerRegistrationProof {
  const ScannerRegistrationProof(this.raw,this.expiresAt);
  final String raw;
  final DateTime expiresAt;
  // Deliberately no serialization method. Never place in journal/log/URL.
}

/// Fixed trusted deployment configuration, never selected by operation input.
/// OFF until an unexposed controller explicitly composes it in a reviewed test.
class ScannerRegistrationTransport {
  ScannerRegistrationTransport({required this.origin,this.enabled=false}) : client=http.Client(),_ownsClient=true { _validateOrigin(); }
  @visibleForTesting
  ScannerRegistrationTransport.forTesting({required this.origin,required this.client,this.enabled=false}) : _ownsClient=false { _validateOrigin(); }
  void _validateOrigin() {
    if(origin.scheme!='https' || origin.host.isEmpty || origin.userInfo.isNotEmpty ||
        !['','/'].contains(origin.path) || origin.hasQuery || origin.hasFragment) { throw ArgumentError('trusted scanner HTTPS origin required'); }
  }
  final Uri origin;
  final http.Client client;
  final bool enabled;
  final bool _ownsClient;
  void close(){if(_ownsClient)client.close();}
  Future<Map<String,dynamic>> _send(ScannerRegistrationSession owner,String requestId,String operation,Map<String,dynamic> fields) async {
    if(!enabled || !_uuid.hasMatch(requestId)) { throw _unavailable(); }
    await owner.verify();
    final clock=Stopwatch()..start();
    final bytes=utf8.encode(jsonEncode({'schema':1,'requestId':requestId,'operation':operation,...fields}));
    if(bytes.length>8192) { throw _unavailable(); }
    final abort=Completer<void>();
    owner.invalidated.then((_) {if(!abort.isCompleted) abort.complete();});
    final timer=Timer(const Duration(seconds:15),(){if(!abort.isCompleted)abort.complete();});
    Duration remaining(){final left=const Duration(seconds:15)-clock.elapsed;if(left<=Duration.zero)throw _unavailable();return left;}
    final request=http.AbortableRequest('POST',origin.resolve('/qr/scanner/registration'),abortTrigger:abort.future)
      ..followRedirects=false..maxRedirects=0
      ..headers.addAll({'content-type':'application/json; charset=utf-8','authorization':'Bearer ${owner.token}'})
      ..bodyBytes=bytes;
    owner.live();
    var retired=false;
    http.StreamedResponse? ownedResponse;
    StreamSubscription<List<int>>? ownedBody;
    void cancelUnconsumed(http.StreamedResponse response){
      try{unawaited(response.stream.listen(null,onError:(Object _){}).cancel().catchError((Object _){}));}catch(_){}
    }
    Future<http.StreamedResponse> send() async {
      final response=await client.send(request);
      if(retired){cancelUnconsumed(response);throw _unavailable();}
      ownedResponse=response;
      return response;
    }
    try {
      final response=await owner.wait(send,remaining());
      remaining();
      if(response.statusCode!=200 || (response.contentLength ?? 0)>16384 ||
          !RegExp(r'^application/json(?:;\s*charset=utf-8)?$',caseSensitive:false).hasMatch(response.headers['content-type']??'')) { throw _unavailable(); }
      final collected=<int>[],done=Completer<void>();
      final body=owner.wait(()=>done.future,remaining());
      ownedBody=response.stream.listen((chunk){
        if(done.isCompleted)return;
        try{owner.live();remaining();if(chunk.length>16384-collected.length)throw _unavailable();collected.addAll(chunk);}
        catch(_){done.completeError(_unavailable());}
      },onDone:(){if(!done.isCompleted)done.complete();},onError:(Object _,StackTrace stack){if(!done.isCompleted)done.completeError(_unavailable(),stack);});
      await body;
      if(clock.elapsed>=const Duration(seconds:15)) { throw _unavailable(); }
      final value=jsonDecode(utf8.decode(collected,allowMalformed:false));owner.live();remaining();
      if(value is! Map<String,dynamic> || value['schema']!=1 || value['requestId']!=requestId || value['operation']!=operation) { throw _unavailable(); }
      return value;
    } catch (_) { throw _unavailable(); }
    finally {
      retired=true;timer.cancel();if(!abort.isCompleted) abort.complete();
      // AbortableRequest alone need not dispose a response after its headers.
      // We own this one response/subscription, never the shared Auth client.
      final subscription=ownedBody;
      if(subscription!=null){try{unawaited(subscription.cancel().catchError((Object _){}));}catch(_){}}
      else{final response=ownedResponse;if(response!=null)cancelUnconsumed(response);}
    }
  }
  Map<String,dynamic> _scope(ScannerRegistrationSession owner,ScannerRegistrationKey key) {
    owner.live();
    if(key.actor!=owner.actor || !_uuid.hasMatch(key.company) || !_uuid.hasMatch(key.device) ||
        !RegExp(r'^302a300506032b6570032100[0-9a-f]{64}$').hasMatch(key.publicKeyHex)) { throw _unavailable(); }
    return {'companyId':key.company,'deviceId':key.device,'publicKeyHex':key.publicKeyHex};
  }
  Future<Map<String,dynamic>?> challenge(ScannerRegistrationSession owner,ScannerRegistrationKey key,String requestId,{required bool reconcile}) async {
    final value=await _send(owner,requestId,reconcile?'challenge_result':'challenge',_scope(owner,key));
    if(value.length!=4 || !value.containsKey('challenge')) { throw _unavailable(); }
    final c=value['challenge'];if(c==null && reconcile) return null;
    if(c is! Map<String,dynamic> || c.length!=10 ||
        !['id','nonce'].every((k)=>c[k] is String && _uuid.hasMatch(c[k] as String)) ||
        c['company']!=key.company || c['actor']!=owner.actor || c['session']!=owner.sid || c['device']!=key.device || c['keyHex']!=key.publicKeyHex ||
        !['createdMs','expiresMs','databaseNowMs'].every((k)=>c[k] is int && (c[k] as int).abs()<=9007199254740991) ||
        c['expiresMs']<=c['createdMs'] || c['expiresMs']-c['createdMs']>90000 || c['databaseNowMs']<c['createdMs'] || c['databaseNowMs']>=c['expiresMs']) { throw _unavailable(); }
    return Map<String,dynamic>.unmodifiable(c);
  }
  Future<ScannerRegistrationProof?> proof(ScannerRegistrationSession owner,String requestId,String challengeId,String password) async {
    if(!_uuid.hasMatch(challengeId) || password.length>1024) { throw _unavailable(); }
    final value=await _send(owner,requestId,'proof',{'challengeId':challengeId,'password':password});
    if(value['accepted']==false && value.length==4) return null;
    if(value.length!=6 || value['accepted']!=true || value['proof'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(value['proof'] as String) || value['expiresAt'] is! String) { throw _unavailable(); }
    final expiry=DateTime.tryParse(value['expiresAt'] as String);
    if(expiry==null || !expiry.isAfter(DateTime.now().toUtc())) { throw _unavailable(); }
    return ScannerRegistrationProof(value['proof'] as String,expiry);
  }
  Future<String> proofStatus(ScannerRegistrationSession owner,String requestId,String challengeId) async {
    if(!_uuid.hasMatch(challengeId)) { throw _unavailable(); }
    final value=await _send(owner,requestId,'proof_result',{'challengeId':challengeId});
    final status=value['issuance'];
    if(value.length!=4 || status is! Map || status.length!=1 || !['not_found','committed_unrecoverable'].contains(status['status'])) { throw _unavailable(); }
    return status['status'] as String;
  }
  Future<void> complete(ScannerRegistrationSession owner,ScannerRegistrationKey key,String requestId,String challengeId,String signature,ScannerRegistrationProof proof) async {
    _scope(owner,key);
    if(!_uuid.hasMatch(challengeId) || !RegExp(r'^[A-Za-z0-9_-]{86}$').hasMatch(signature) || !proof.expiresAt.isAfter(DateTime.now().toUtc())) { throw _unavailable(); }
    final value=await _send(owner,requestId,'complete',{'challengeId':challengeId,'signature':signature,'proof':proof.raw});
    if(value.length!=4 || value['deviceId']!=key.device) { throw _unavailable(); }
  }
  Future<String?> receipt(ScannerRegistrationSession owner,ScannerRegistrationKey key,String requestId,String challengeId) async {
    if(!_uuid.hasMatch(challengeId)) { throw _unavailable(); }
    final value=await _send(owner,requestId,'result',{'challengeId':challengeId,..._scope(owner,key)});
    if(value.length!=4 || !value.containsKey('receipt')) { throw _unavailable(); }
    final receipt=value['receipt'];if(receipt==null) return null;
    if(receipt is! Map || receipt.length!=3 || receipt['challengeId']!=challengeId || receipt['deviceId']!=key.device ||
        receipt['registrationEventId'] is! String || !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(receipt['registrationEventId'] as String) ||
        BigInt.parse(receipt['registrationEventId'] as String)>BigInt.parse('9223372036854775807')) { throw _unavailable(); }
    return receipt['registrationEventId'] as String;
  }
}
