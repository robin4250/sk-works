import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'admin_saved_qualification_photo_contract.dart';
import 'admin_saved_qualification_photo_draft_page.dart';
import 'admin_saved_qualification_photo_submission_repository.dart';

/// Registered retained-photo changes only. No metadata or new-upload controls.
class AdminSavedQualificationPhotoPage extends StatefulWidget {
  const AdminSavedQualificationPhotoPage({super.key,required this.row,required this.current,
    this.repository,this.photoBuilder,this.invalidations});
  final Listenable? invalidations;
  @visibleForTesting
  final AdminSavedQualificationSubmissionRepository? repository;
  @visibleForTesting
  final Widget Function(BuildContext,String)? photoBuilder;
  final Map<String,dynamic> row;
  final bool Function() current;
  @override
  State<AdminSavedQualificationPhotoPage> createState()=>_AdminSavedQualificationPhotoPageState();
}
class _AdminSavedQualificationPhotoPageState extends State<AdminSavedQualificationPhotoPage> with WidgetsBindingObserver {
  late final String _initialRow;
  late final bool Function() _initialCurrent;
  late final AdminSavedQualificationSubmissionRepository? _initialRepository;
  bool get _pageCurrent {
    try {return !_retired && identical(widget.current,_initialCurrent) &&
      identical(widget.repository,_initialRepository) && jsonEncode(widget.row)==_initialRow && widget.current();}
    catch(_){return false;}
  }
  LiveAdminSavedQualificationPort? _port;
  AdminSavedQualificationSubmissionRepository? _repository;
  AdminSavedQualificationPhotoCapability _cap=AdminSavedQualificationPhotoCapability.unavailable;
  final _scope=ValueNotifier(const AdminSavedQualificationPhotoScope());
  bool _busy=true,_retired=false;
  String? _message;
  Map<String,dynamic>? _journal;
  @override
  void initState(){
    super.initState();_initialRow=jsonEncode(widget.row);_initialCurrent=widget.current;
    _initialRepository=widget.repository;
    WidgetsBinding.instance.addObserver(this);
    widget.invalidations?.addListener(_invalidate);
    if(const [AppLifecycleState.paused,AppLifecycleState.hidden,AppLifecycleState.detached]
      .contains(WidgetsBinding.instance.lifecycleState)){
      _retired=true;_busy=false;
    }else{_open();}
  }
  @override
  void didUpdateWidget(covariant AdminSavedQualificationPhotoPage oldWidget){
    super.didUpdateWidget(oldWidget);
    if(!identical(oldWidget.invalidations,widget.invalidations)){
      oldWidget.invalidations?.removeListener(_invalidate);
      _invalidate();
    }
    if(!_pageCurrent || !identical(oldWidget.photoBuilder,widget.photoBuilder)){_invalidate();}
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(const [AppLifecycleState.paused,AppLifecycleState.hidden,AppLifecycleState.detached].contains(state)){
      _invalidate();
    }
  }
  void _invalidate(){
    if (_retired || !mounted) return;
    _scope.value=const AdminSavedQualificationPhotoScope();
    _port?.lease.removeListener(_invalidate);_port?.dispose();_port=null;
    setState((){_retired=true;_cap=AdminSavedQualificationPhotoCapability.unavailable;
      _message='ログイン・会社・資格の状態が変わりました。申請は再送せず、画面を開き直して同じ申請を確認してください。';});
  }
  Future<void> _open() async {
    try {
      if (!_pageCurrent || (widget.repository==null && !SupabaseBackend.isInitialized)) {
        throw StateError('資格の表示状態を確認してください。');
      }
      final target=widget.repository?.target ?? AdminSavedQualificationTarget(widget.row);
      final port=widget.repository?.port ??
        LiveAdminSavedQualificationPort(SupabaseBackend.client,target,current:()=>_pageCurrent);
      if(port is LiveAdminSavedQualificationPort){
        _port=port;port.lease.addListener(_invalidate);
      }
      final repository=widget.repository ?? AdminSavedQualificationSubmissionRepository(port,target);
      _repository=repository;
      final cap=await repository.capability();
      final journal=await repository.journal();
      if (!mounted || _retired) return;
      _scope.value=AdminSavedQualificationPhotoScope(companyId:target.company,actorId:port.actor);
      setState((){_cap=cap;_journal=journal;
        _message=cap.available ? null : '管理者の資格写真変更は準備中です。元の画面で保存済み写真を確認できます。';});
    } catch (_) {
      if(mounted && !_retired)setState((){_message='資格写真変更の利用状態を確認できません。再送せず元の画面から確認してください。';});
    } finally {if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _refreshJournal() async {
    final repo=_repository;
    if(repo==null || _retired)return;
    final value=await repo.journal();
    if(mounted && !_retired)setState(()=>_journal=value);
  }
  Widget _photo(BuildContext context,String path) {
    if(widget.photoBuilder!=null)return widget.photoBuilder!(context,path);
    final port=_port;
    if(port==null || _retired)return const Text('写真を再確認してください。');
    return FutureBuilder<String>(
      future:port.signedSavedPhoto(path),
      builder:(context,snapshot){
        if(_retired)return const Text('表示状態が変わりました。');
        if(snapshot.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError || snapshot.data==null)return const Text('写真を表示できません。');
        if(path.toLowerCase().endsWith('.pdf'))return const Center(child:Text('保存済みPDF（原本は元の画面で確認）'));
        return Image.network(snapshot.data!,fit:BoxFit.contain,
          errorBuilder:(_,__,___)=>const Text('写真を表示できません。'));
      });
  }
  Future<void> _edit() async {
    final repo=_repository;
    if(repo==null || _retired || _busy || _journal!=null || !_cap.available)return;
    final port=repo.port;
    final selected=await Navigator.of(context).push<AdminSavedQualificationPhotoDraft>(
      MaterialPageRoute(builder:(_)=>AdminSavedQualificationPhotoDraftPage(
        capability:_cap,companyId:repo.target.company,actorId:port.actor,targetId:repo.target.id,
        savedPaths:repo.target.paths,scope:_scope,photoBuilder:_photo)));
    if(!mounted || selected==null || _retired)return;
    final confirm=await showDialog<bool>(context:context,builder:(dialogContext)=>
      ValueListenableBuilder<AdminSavedQualificationPhotoScope>(valueListenable:_scope,
        builder:(context,scope,_){
          if(!_pageCurrent || scope.companyId!=repo.target.company || scope.actorId!=port.actor){
            return AlertDialog(title:const Text('状態が変わりました'),
              content:const Text('確認内容は非表示にしました。申請は送信しません。元の画面から開き直してください。'),
              actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('閉じる'))]);
          }
          return AlertDialog(
            title:const Text('写真の変更申請を送信'),
            content:Text('保存済み写真 ${selected.savedPaths.length}件から ${selected.selectedPaths.length}件を残す変更を申請します。別の管理者・承認担当者の承認後に反映します。元の写真ファイルは保持します。'),
            actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('送信しない')),
              FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('申請を送信'))]);
        }));
    if(!mounted || confirm!=true || !_pageCurrent){if(mounted && !_pageCurrent)_invalidate();return;}
    setState(()=>_busy=true);
    try {
      final result=await repo.submit(selected.selectedPaths);
      if(mounted && !_retired){setState(()=>_message=result.status=='approved'
        ? '写真変更の承認結果を確認しました。元の画面を再読み込みしてください。'
        : '申請受付を確認しました。「承認待ち」→「資格写真の承認待ち」で別担当者が確認します。');}
    } catch (_) {
      if(mounted && !_retired)setState(()=>_message='申請結果を確認できません。再送せず「同じ申請を再確認」で状態を確認してください。');
    } finally {
      try{await _refreshJournal();}catch(_){}
      if(mounted)setState(()=>_busy=false);
    }
  }
  Future<void> _reconcile({bool acknowledge=false}) async {
    final repo=_repository;
    if(repo==null || _retired || _busy)return;
    setState(()=>_busy=true);
    try {
      if(acknowledge){await repo.acknowledgeFinal(); if(mounted)Navigator.pop(context);return;}
      else {
        final result=await repo.reconcile();
        if(mounted && !_retired){setState(()=>_message=switch(result?.status){
          'draft'=>'下書きの保存を確認しました。送信完了ではありません。再送せず管理者へ確認してください。',
          'pending'=>'承認待ちです。再送せず承認結果をお待ちください。',
          'approved'=>'承認済みです。元の画面を再読み込みしてください。',
          'rejected'=>'却下・取消の結果を確認しました。',
          _=>'同じ申請の結果を確認できません。再送しないでください。'});}
      }
      await _refreshJournal();
    } catch (_) {
      if(mounted && !_retired)setState(()=>_message='同じ申請の結果を確認できません。保存済みの申請情報は保持しています。再送しないでください。');
    } finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  void dispose(){
    _retired=true;_scope.value=const AdminSavedQualificationPhotoScope();
    WidgetsBinding.instance.removeObserver(this);widget.invalidations?.removeListener(_invalidate);
    _port?.lease.removeListener(_invalidate);_port?.dispose();_scope.dispose();super.dispose();
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('資格写真の変更申請')),
    body:_retired ? const Center(child:Text('表示状態が変わりました。元の画面から開き直してください。')) : SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('保存済み写真の並べ替え・除外だけを申請できます。新しい写真の追加と資格番号・有効期限などの内容変更は準備中です。'),
      if(_message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Text(_message!)),
      if(_busy)const Center(child:CircularProgressIndicator()),
      if(!_retired && _journal!=null)...[
        const Text('保存された申請があります。新しい申請は送信しません。'),
        OutlinedButton(onPressed:_busy?null:()=>_reconcile(),child:const Text('同じ申請を再確認')),
        if(const ['approved','rejected'].contains(_journal!['stage']))
          OutlinedButton(onPressed:_busy?null:()=>_reconcile(acknowledge:true),
            child:const Text('確定した申請結果を確認して閉じる')),
      ],
      if(!_retired && _journal==null && _cap.available)
        FilledButton(onPressed:_busy?null:_edit,child:const Text('残す写真・順番を選ぶ')),
      OutlinedButton(onPressed:()=>Navigator.pop(context),child:const Text('閉じる')),
    ])));
}
