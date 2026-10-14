import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';

/// A saved contract may never survive an account switch on the preview stack.
class TradeDocumentActorBoundary extends StatefulWidget {
 const TradeDocumentActorBoundary({super.key,required this.child,this.initialActor,this.actorChanges});
 final Widget child;
 @visibleForTesting final String? initialActor;
 @visibleForTesting final Stream<String?>? actorChanges;
 @override State<TradeDocumentActorBoundary> createState()=>_BoundaryState();
}
class _BoundaryState extends State<TradeDocumentActorBoundary> {
 String? _actor;bool _revoked=false;StreamSubscription<dynamic>? _subscription;
 @override void initState(){super.initState();
  if(!SupabaseBackend.isInitialized&&widget.actorChanges==null)return;
  _actor=widget.initialActor??(SupabaseBackend.isInitialized?SupabaseBackend.client.auth.currentUser?.id:null);_revoked=_actor==null;
  final changes=widget.actorChanges??SupabaseBackend.client.auth.onAuthStateChange.map((event)=>event.session?.user.id);
  _subscription=changes.listen((actor){
   if(mounted&&!_revoked&&actor!=_actor)setState(()=>_revoked=true);
  },onError:(_){if(mounted)setState(()=>_revoked=true);});
 }
 @override void dispose(){_subscription?.cancel();super.dispose();}
 @override Widget build(BuildContext context)=>_revoked?Scaffold(appBar:AppBar(title:const Text('帳票')),
  body:const Center(child:Text('ログイン情報が変わりました。画面を閉じて開き直してください。'))):widget.child;
}

/// Sticky lease for asynchronous PDF generation and the OS handoff boundary.
class TradeDocumentActorLease {
 TradeDocumentActorLease({@visibleForTesting String? initialActor,@visibleForTesting Stream<String?>? actorChanges}){
  if(!SupabaseBackend.isInitialized&&actorChanges==null)return;
  _actor=initialActor??(SupabaseBackend.isInitialized?SupabaseBackend.client.auth.currentUser?.id:null);_revoked=_actor==null;
  final changes=actorChanges??SupabaseBackend.client.auth.onAuthStateChange.map((event)=>event.session?.user.id);
  _subscription=changes.listen((actor){
    if(actor!=_actor)_revoked=true;
  },onError:(_){_revoked=true;});
 }
 String? _actor;bool _revoked=false;StreamSubscription<dynamic>? _subscription;
 void verify(){
  if(_revoked||(SupabaseBackend.isInitialized&&SupabaseBackend.client.auth.currentUser?.id!=_actor)){
   throw StateError('ログイン情報が変わりました。開き直してください。');
  }
 }
 void dispose(){_subscription?.cancel();}
}
