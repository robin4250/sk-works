import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';

/// A saved contract may never survive an account switch on the preview stack.
class TradeDocumentActorBoundary extends StatefulWidget {
 const TradeDocumentActorBoundary({super.key,required this.child});
 final Widget child;
 @override State<TradeDocumentActorBoundary> createState()=>_BoundaryState();
}
class _BoundaryState extends State<TradeDocumentActorBoundary> {
 String? _actor;bool _revoked=false;StreamSubscription<dynamic>? _subscription;
 @override void initState(){super.initState();
  if(!SupabaseBackend.isInitialized)return;
  _actor=SupabaseBackend.client.auth.currentUser?.id;_revoked=_actor==null;
  _subscription=SupabaseBackend.client.auth.onAuthStateChange.listen((event){
   if(mounted&&!_revoked&&event.session?.user.id!=_actor)setState(()=>_revoked=true);
  },onError:(_){if(mounted)setState(()=>_revoked=true);});
 }
 @override void dispose(){_subscription?.cancel();super.dispose();}
 @override Widget build(BuildContext context)=>_revoked?Scaffold(appBar:AppBar(title:const Text('帳票')),
  body:const Center(child:Text('ログイン情報が変わりました。画面を閉じて開き直してください。'))):widget.child;
}

/// Sticky lease for asynchronous PDF generation and the OS handoff boundary.
class TradeDocumentActorLease {
 TradeDocumentActorLease(){
  if(!SupabaseBackend.isInitialized)return;
  _actor=SupabaseBackend.client.auth.currentUser?.id;_revoked=_actor==null;
  _subscription=SupabaseBackend.client.auth.onAuthStateChange.listen((event){
    if(event.session?.user.id!=_actor)_revoked=true;
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
