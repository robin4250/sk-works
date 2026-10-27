import 'dart:async';
import 'package:flutter/material.dart';
import 'security_notice_repository.dart';

class SecurityNoticePage extends StatefulWidget {
  const SecurityNoticePage({super.key,this.repository});
  final SecurityNoticeRepository? repository;
  @override State<SecurityNoticePage> createState()=>_SecurityNoticePageState();
}
class _SecurityNoticePageState extends State<SecurityNoticePage> with WidgetsBindingObserver {
  late final SecurityNoticeRepository? _repo;
  final _password=TextEditingController();
  StreamSubscription<String?>? _subscription;
  String? _session,_error;
  List<Map<String,dynamic>>? _items;
  SecurityNoticeCommand? _pending;
  bool _busy=false,_revoked=false,_active=true;
  int _generation=0, _capacityGaps=0;
  @override void initState(){super.initState();_repo=widget.repository??SecurityNoticeRepository.maybeCreate();_session=_repo?.collector.sessionKey();_active=(WidgetsBinding.instance.lifecycleState??AppLifecycleState.resumed)==AppLifecycleState.resumed;WidgetsBinding.instance.addObserver(this);
    _subscription=_repo?.collector.sessionChanges.listen((value){if(value!=_session || _repo.collector.sessionKey()!=_session)_revoke();},onError:(Object _)=>_revoke());}
  void _revoke(){if(!mounted)return;setState((){_generation++;_password.clear();_items=null;_capacityGaps=0;_busy=false;_revoked=true;_error='本人確認が失効しました。操作結果は再ログイン後に一覧で確認してください。';});}
  @override void didChangeAppLifecycleState(AppLifecycleState state){_active=state==AppLifecycleState.resumed;if(!_active && mounted)setState((){_generation++;_password.clear();_items=null;_capacityGaps=0;_busy=false;_error='表示を消しました。再認証して確認してください。';});}
  bool _current(int generation)=>mounted&&_active&&!_revoked&&generation==_generation;
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);_generation++;_subscription?.cancel();_password.clear();_password.dispose();super.dispose();}
  Future<void> _load() async {
    final repo=_repo;
    if(repo==null||_password.text.isEmpty||_busy||_revoked||!_active||_pending!=null)return;
    FocusScope.of(context).unfocus();final pwd=_password.text;_password.clear();final g=++_generation;
    setState((){_busy=true;_error=null;_items=null;});
    try{final snapshot=await repo.load(pwd,isActive:()=>_current(g));if(_current(g))setState((){_items=snapshot.events;_capacityGaps=snapshot.capacityGaps;});}
    catch(_){if(_current(g))setState(()=>_error='通知は準備中か、本人確認・接続を確認できません。記録なしを意味しません。');}
    finally{if(_current(g))setState(()=>_busy=false);}
  }
  Future<void> _start(Map<String,dynamic> item,String action) async {
    if(_pending!=null||_busy||_revoked)return;
    String reason='';
    if(action!='read'){
      final value=await showDialog<String>(context:context,builder:(_)=>const _ReasonDialog());
      if(value==null||!mounted)return;reason=value;
    }
    setState(()=>_pending=SecurityNoticeCommand(eventId:item['event_id'],action:action,reason:reason,revision:item['revision'],commandId:SecurityNoticeCommand.newId()));
    await _runPending();
  }
  Future<void> _runPending() async {
    final cmd=_pending,repo=_repo;
    if(cmd==null||repo==null||_password.text.isEmpty||_busy||_revoked||!_active)return;
    FocusScope.of(context).unfocus();final pwd=_password.text;_password.clear();final g=++_generation;
    setState((){_busy=true;_error=null;});
    var saved=false;
    try{
      await repo.update(cmd,pwd,isActive:()=>_current(g));saved=true;
      if(_current(g))setState(()=>_pending=null);
      final snapshot=await repo.load(pwd,isActive:()=>_current(g));
      if(_current(g))setState((){_items=snapshot.events;_capacityGaps=snapshot.capacityGaps;_error='対応を保存しました。';});
    }catch(error){if(_current(g))setState((){
      if(saved){_items=null;_error='対応は保存済みです。再認証して一覧を更新してください。';}
      else if(error is SecurityNoticeRejected){_pending=null;_items=null;_error='操作結果を確認できません。再認証し、最新の一覧で確認してください。';}
      else {_error='結果を確認できません。同じ操作を再確認してください。';}
    });}
    finally{if(_current(g))setState(()=>_busy=false);}
  }
  String _state(String x)=>const {'unreviewed':'未対応','investigating':'確認中','false_positive':'誤検知','resolved':'対応済み'}[x]??'状態不明';
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('監視の通知・対応')),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('検知対象への接触記録です。攻撃の確定や人物の特定ではありません。停止や欠落を、この一覧だけでは判断できません。'),
      if(_error!=null) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(_error!)),
      if(!_revoked)...[
        TextField(key:const ValueKey('notice-password'),controller:_password,enabled:!_busy,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(labelText:'ログインパスワード（本人確認）')),
        if(_pending==null) FilledButton(onPressed:_busy?null:_load,child:const Text('本人確認して一覧を表示')),
        if(_pending!=null) FilledButton(onPressed:_busy?null:_runPending,child:const Text('同じ操作を再確認')),
      ],
      if(_busy)const LinearProgressIndicator(),
      if(_items!=null && _capacityGaps>0) Text('上限に達し、通知に記録できなかった観測が$_capacityGaps件あります。収集記録を管理者が確認してください。',style:const TextStyle(color:Colors.red)),
      if(_items case final rows?) ...[
        if(rows.isEmpty)const Text('対象範囲の通知はありません。監視の正常性を示すものではありません。'),
        for(final row in rows) Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(row['event_kind']=='current_lure_touched'?'現在の監視対象への接触':'以前の監視対象への接触',style:Theme.of(context).textTheme.titleMedium),
          Text('${row['occurred_at']} ・ ${_state(row['review_state'])}'),
          if(row['review_reason']!=null)Text('対応内容：${row['review_reason']}'),
          if(row['read_at']!=null)const Text('確認済み'),
          if(row['read_at']==null)TextButton(onPressed:_busy||_pending!=null?null:()=>_start(row,'read'),child:const Text('確認済みにする')),
          Wrap(children:[for(final entry in const {'investigating':'確認中','false_positive':'誤検知','resolved':'対応済み'}.entries)
            TextButton(onPressed:_busy||_pending!=null?null:()=>_start(row,entry.key),child:Text(entry.value))]),
        ]))),
      ],
    ]));
}
class _ReasonDialog extends StatefulWidget {const _ReasonDialog();@override State<_ReasonDialog> createState()=>_ReasonDialogState();}
class _ReasonDialogState extends State<_ReasonDialog>{final _reason=TextEditingController();@override void dispose(){_reason.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('対応内容を記録'),content:TextField(controller:_reason,maxLength:500,onChanged:(_)=>setState((){}),decoration:const InputDecoration(labelText:'理由・対応内容（必須）')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('戻る')),TextButton(onPressed:_reason.text.trim().isEmpty?null:()=>Navigator.pop(context,_reason.text.trim()),child:const Text('決定'))]);
}
