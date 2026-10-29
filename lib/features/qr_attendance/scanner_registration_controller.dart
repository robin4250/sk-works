import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'scanner_registration_key.dart';
import 'scanner_registration_pending.dart';
import 'scanner_registration_transport.dart';

class _RecoveryBlocked implements Exception { const _RecoveryBlocked(); }

enum ScannerRegistrationView { disabled,loading,newLogicalDevice,keyPreparation,ready,password,wrongPassword,busy,uncertain,proofLost,confirmed,blocked }

/// Unexposed/OFF composition of the actual native custody and HTTPS contract.
/// No routing, permission inference, attendance write, or automatic retry.
class ScannerRegistrationController extends ChangeNotifier {
 ScannerRegistrationController({required this.client,required this.company,required this.keys,required this.journal,required this.transport,this.enabled=false});
 final SupabaseClient client;
 final String company;
 final ScannerRegistrationKeyCustody keys;
 final ScannerRegistrationJournal journal;
 final ScannerRegistrationTransport transport;
 final bool enabled;
 ScannerRegistrationView view=ScannerRegistrationView.disabled;
 ScannerRegistrationPending? pending;
 ScannerRegistrationSession? _owner;
 bool _disposed=false,_busy=false,_setupAttempted=false;
 int _epoch=0;
 bool get busy=>_busy;
 bool get canReconcile=>!_busy && pending!=null && ![ScannerRegistrationView.blocked,ScannerRegistrationView.disabled].contains(view);
 void _emit(ScannerRegistrationView next){if(_disposed)return;view=next;notifyListeners();}
 void _live(int epoch){if(_disposed || epoch!=_epoch)throw StateError('登録手続きが変更されました。');_owner!.live();}
 Future<void> load() async {
  if(_disposed || _busy)return;
  if(!enabled){_emit(ScannerRegistrationView.disabled);return;}
  final old=_owner;_owner=null;final loadingEpoch=++_epoch;await old?.dispose();
  // Disposal or a newer load may retire this continuation while cancellation
  // is pending (including the initial await-null microtask). Never reacquire.
  if(_disposed || loadingEpoch!=_epoch)return;
  try {
   final owner=ScannerRegistrationSession(client);_owner=owner;
   owner.invalidated.then((_) {if(!_disposed && identical(_owner,owner)){_epoch++;_busy=false;_emit(ScannerRegistrationView.blocked);}});
  }catch(_){_emit(ScannerRegistrationView.blocked);return;}
  await _run((epoch) async {
   ScannerRegistrationPending? value;
   try{value=await journal.read(_owner!,company);}catch(_){throw const _RecoveryBlocked();}_live(epoch);
   if(value==null){if(pending!=null || _setupAttempted)throw const _RecoveryBlocked();_emit(ScannerRegistrationView.newLogicalDevice);return;}
   _adopt(value);await _reconcile(epoch);
  });
 }
 void _adopt(ScannerRegistrationPending value){
  final old=pending;
  if(old!=null && (!old.sameImmutable(value) || value.version<old.version))throw const _RecoveryBlocked();pending=value;
 }
 Future<void> _run(Future<void> Function(int epoch) action) async {
  if(_disposed || _busy || !enabled || _owner==null)return;
  final epoch=_epoch;_busy=true;_emit(ScannerRegistrationView.busy);
  try{_live(epoch);await action(epoch);_live(epoch);}
  catch(error){if(!_disposed && epoch==_epoch){var live=true;try{_owner!.live();}catch(_){live=false;}_emit(error is _RecoveryBlocked||!live||pending==null?ScannerRegistrationView.blocked:ScannerRegistrationView.uncertain);}}
  finally{if(!_disposed && epoch==_epoch){_busy=false;notifyListeners();}}
 }
 Future<void> _advance(int epoch,String next,Map<String,dynamic> patch) async {
  final value=await journal.advance(_owner!,pending!,next,patch);_live(epoch);_adopt(value);
 }
 Future<void> createExplicitNewLogicalDevice() async {
  if(view!=ScannerRegistrationView.newLogicalDevice || _setupAttempted)return;
  _setupAttempted=true;
  await _run((epoch) async {
   // Native local presence precedes the durable initial intent. No remote write.
   final value=await journal.createExplicitNewLogicalDevice(_owner!,company);_live(epoch);_adopt(value);_emit(ScannerRegistrationView.keyPreparation);
  });
 }
 Future<void> prepareKey() async {
  if(pending?.stage!='key_pending')return;
  await _run((epoch) async {
   await _owner!.verify();_live(epoch);
   final key=await keys.prepare(company:company,device:pending!.data['device'] as String);_live(epoch);
   if(key.actor!=pending!.data['actor'] || key.handle!=pending!.data['handle'])throw StateError('鍵が一致しません。');
   await _advance(epoch,'key_ready',{'publicKeyHex':key.publicKeyHex});_emit(ScannerRegistrationView.ready);
  });
 }
 Future<void> startChallenge() async {
  if(pending?.stage!='key_ready')return;
  await _run((epoch) async {
   final requestId=scannerRequestId();await _advance(epoch,'challenge_sent',{'challengeRequestId':requestId});
   final value=await transport.challenge(_owner!,pending!.key,requestId,reconcile:false);_live(epoch);
   if(value==null)throw StateError('チャレンジを確認できません。');
   await _advance(epoch,'challenge_ready',{'challenge':value});_emit(ScannerRegistrationView.password);
  });
 }
 Future<Map<String,dynamic>> _currentChallenge(int epoch) async {
  final value=await transport.challenge(_owner!,pending!.key,scannerRequestId(),reconcile:true);_live(epoch);
  final old=pending!.challenge;
  if(value==null || old==null || !['id','actor','company','session','device','keyHex','nonce','createdMs','expiresMs'].every((k)=>value[k]==old[k]))throw StateError('元のチャレンジを確認できません。');
  return value;
 }
 Future<void> submitPassword(String password) async {
  if(!['challenge_ready','proof_rejected'].contains(pending?.stage) || password.length>1024 || (pending!.data['proofRequestIds'] as List).length>=5)return;
  await _run((epoch) async {
   await _currentChallenge(epoch);
   final proofRequestId=scannerRequestId();await _advance(epoch,'proof_sent',{'proofRequestId':proofRequestId});
   final proof=await transport.proof(_owner!,proofRequestId,pending!.challenge!['id'] as String,password);password='';_live(epoch);
   if(proof==null){await _advance(epoch,'proof_rejected',{});_emit(ScannerRegistrationView.wrongPassword);return;}
   await _advance(epoch,'proof_delivered',{});
   final challenge=await _currentChallenge(epoch);await _owner!.verify();_live(epoch);
   final signature=await keys.signRegistration(key:pending!.key,challenge:challenge);_live(epoch);
   final completionRequestId=scannerRequestId();await _advance(epoch,'completion_sent',{'completionRequestId':completionRequestId});
   await transport.complete(_owner!,pending!.key,completionRequestId,challenge['id'] as String,signature,proof);_live(epoch);
   // Even a known 200 completion is followed by the exact immutable receipt.
   await _readReceipt(epoch);
  });
 }
 Future<void> reconcile() async {
  if(!canReconcile)return;
  await _run((epoch) async {
   ScannerRegistrationPending? value;
   try{value=await journal.read(_owner!,company);}catch(_){throw const _RecoveryBlocked();}_live(epoch);
   if(value==null)throw const _RecoveryBlocked();_adopt(value);await _reconcile(epoch);
  });
 }
 Future<void> _readReceipt(int epoch) async {
  final receipt=await transport.receipt(_owner!,pending!.key,scannerRequestId(),pending!.challenge!['id'] as String);_live(epoch);
  if(receipt==null)throw StateError('登録結果を確認できません。');
  if(pending!.stage=='confirmed'){if(pending!.data['registrationEventId']!=receipt)throw StateError('元の履歴が一致しません。');}
  else{await _advance(epoch,'confirmed',{'registrationEventId':receipt});}
  _emit(ScannerRegistrationView.confirmed);
 }
 Future<void> _reconcile(int epoch) async {
  switch(pending!.stage){
   case 'key_pending':_emit(ScannerRegistrationView.keyPreparation);return;
   case 'key_ready':_emit(ScannerRegistrationView.ready);return;
   case 'challenge_sent':
    final value=await transport.challenge(_owner!,pending!.key,scannerRequestId(),reconcile:true);_live(epoch);
    if(value==null)throw StateError('チャレンジの結果が不明です。');await _advance(epoch,'challenge_ready',{'challenge':value});_emit(ScannerRegistrationView.password);return;
   case 'challenge_ready':await _currentChallenge(epoch);_emit(ScannerRegistrationView.password);return;
   case 'proof_rejected':await _currentChallenge(epoch);_emit(ScannerRegistrationView.wrongPassword);return;
   case 'proof_sent':case 'proof_delivered':case 'proof_lost':
    final status=await transport.proofStatus(_owner!,scannerRequestId(),pending!.challenge!['id'] as String);_live(epoch);
    if(status!='committed_unrecoverable')throw StateError('本人確認の結果が不明です。');
    if(pending!.stage!='proof_lost')await _advance(epoch,'proof_lost',{});
    _emit(ScannerRegistrationView.proofLost);return;
   case 'completion_sent':case 'confirmed':await _readReceipt(epoch);return;
   default:throw StateError('元の手続きを確認できません。');
  }
 }
 @override void dispose(){if(_disposed)return;_disposed=true;_epoch++;final owner=_owner;_owner=null;unawaited(owner?.dispose()??Future<void>.value());keys.dispose();transport.close();super.dispose();}
}
