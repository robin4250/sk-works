import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'company_common_payroll_publication_repository.dart';
import 'company_common_payroll_publication_summary.dart';

class CompanyCommonPayrollPublicationPanel extends StatefulWidget {
  const CompanyCommonPayrollPublicationPanel({super.key, required this.companyId, this.repository,
    this.enabled = true, this.canReconcile = true, this.onBusyChanged, this.initialPayrollType = 'hourly'});
  final String companyId;
  final CommonPayrollPublicationRepository? repository;
  final bool enabled;
  final bool canReconcile;
  final String initialPayrollType;
  final ValueChanged<bool>? onBusyChanged;
  @override State<CompanyCommonPayrollPublicationPanel> createState()=>_CompanyCommonPayrollPublicationPanelState();
}
class _CompanyCommonPayrollPublicationPanelState extends State<CompanyCommonPayrollPublicationPanel> with WidgetsBindingObserver {
  CommonPayrollPublicationRepository? _repository;
  StreamSubscription<String?>? _subscription;
  String? _session;
  CommonPayrollPublicationState? _state;
  CommonPayrollPublicationRequest? _pending;
  String? _error;
  bool _busy=false,_confirming=false,_revoked=false,_active=true,_showApplicationSummary=false;
  int _generation=0;
  String _type='hourly';
  late DateTime _month;
  BuildContext? _dialog;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _completionNotice;
  void _hideApplicationSummary(){_showApplicationSummary=false;_completionNotice?.close();_completionNotice=null;}
  DateTime get _currentMonth {final now=DateTime.now().toUtc().add(const Duration(hours:9));return DateTime(now.year,now.month);}
  String get _monthKey=>'${_month.year}-${_month.month.toString().padLeft(2,'0')}-01';
  bool _valid(int generation)=>mounted && generation==_generation && !_revoked && _active && _repository?.sessionKey==_session;
  @override void initState(){super.initState();_month=_currentMonth;_type=['daily','hourly','monthly'].contains(widget.initialPayrollType)?widget.initialPayrollType:'hourly';_repository=widget.repository??SupabaseCommonPayrollPublicationRepository.maybeCreate();_session=_repository?.sessionKey;
    _subscription=_repository?.sessionChanges.listen((key){if(key!=_session)_revoke();},onError:(Object _)=>_revoke());
    WidgetsBinding.instance.addObserver(this);_active=WidgetsBinding.instance.lifecycleState==null||WidgetsBinding.instance.lifecycleState==AppLifecycleState.resumed;unawaited(_load());}
  @override void didUpdateWidget(covariant CompanyCommonPayrollPublicationPanel old){super.didUpdateWidget(old);if(old.companyId!=widget.companyId){_generation++;_closeDialog();_state=null;_pending=null;_error=null;_hideApplicationSummary();_month=_currentMonth;unawaited(_load());}}
  void _closeDialog(){final dialog=_dialog;_dialog=null;if(dialog!=null)WidgetsBinding.instance.addPostFrameCallback((_){if(dialog.mounted&&ModalRoute.of(dialog)?.isCurrent==true)Navigator.of(dialog).pop(false);});}
  void _revoke(){if(!mounted)return;_generation++;setState((){_revoked=true;_hideApplicationSummary();_state=null;_error='ログイン状態が変わりました。この画面を開き直してください。';});widget.onBusyChanged?.call(true);_closeDialog();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){_active=state==AppLifecycleState.resumed;if(!_active){_generation++;_hideApplicationSummary();_closeDialog();if(mounted)setState(()=>_state=null);}else if(!_revoked){unawaited(_load());}}
  Future<void> _load() async {
    final repository=_repository;if(repository==null||_revoked||!_active)return;final generation=++_generation;
    setState((){_busy=true;_hideApplicationSummary();});
    try{final value=await repository.read(widget.companyId);if(!_valid(generation))return;setState((){_state=value;_error=null;});}
    catch(_){if(_valid(generation))setState(()=>_error='給与への適用設定を取得できません。サーバー準備状況を確認してください。');}
    finally{if(mounted&&generation==_generation)setState(()=>_busy=false);}
  }
  Future<void> _start() async {
    final state=_state;final generation=_generation;if(state==null||!state.canEdit||!widget.enabled||_busy||_confirming||_pending!=null||!_valid(generation))return;
    setState((){_confirming=true;_hideApplicationSummary();});widget.onBusyChanged?.call(true);
    bool? accepted;
    try {
    accepted=await showDialog<bool>(context:context,builder:(context){_dialog=context;return AlertDialog(
      title:const Text('保存済み共通手当を給与へ適用'),
      content:Text('${_typeLabel(_type)}の保存済み共通手当を${_month.year}年${_month.month}月から適用し、自動下書きを再計算します。未保存の編集は含みません。確定済み・手入力の給与は保持します。'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('戻る')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('適用する'))],);});
    } finally { _dialog=null; if(mounted){setState(()=>_confirming=false);widget.onBusyChanged?.call(_pending!=null||_revoked);} }
    if(!_valid(generation)||widget.companyId!=state.companyId||accepted!=true||!widget.enabled)return;
    _pending=CommonPayrollPublicationRequest(state,_type,_monthKey);await _applyPending();
  }
  Future<void> _applyPending() async {
    final request=_pending;final repository=_repository;if(request==null||request.state.companyId!=widget.companyId||repository==null||_busy||_revoked||!_active||!widget.canReconcile)return;
    final generation=_generation;setState((){_busy=true;_hideApplicationSummary();});widget.onBusyChanged?.call(true);
    try{final value=await repository.publish(request);if(!mounted||!_valid(generation))return;setState((){_state=value;_pending=null;_error=null;_showApplicationSummary=true;});_completionNotice=ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text((value.applicationSummary??const CommonPayrollPublicationSummary()).message)));}
    catch(error){if(!_valid(generation))return;final rejected=error is PostgrestException&&['42501','40001','22023','55000','PGRST202'].contains(error.code);setState((){if(rejected){_pending=null;_state=null;}_error=rejected?'適用できませんでした。設定を再読み込みして確認してください。':'適用結果を確認できません。同じ内容で適用結果を確認してください。';});}
    finally{if(mounted&&generation==_generation){setState(()=>_busy=false);widget.onBusyChanged?.call(_pending!=null);}}
  }
  String _typeLabel(String type)=>const {'daily':'日給','hourly':'時給','monthly':'月給'}[type]!;
  @override void dispose(){_generation++;final notice=_completionNotice;_completionNotice=null;if(notice!=null)WidgetsBinding.instance.addPostFrameCallback((_)=>notice.close());_subscription?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext context){
    if(_repository==null)return const SizedBox.shrink();
    if(_revoked)return Padding(padding:const EdgeInsets.all(12),child:Text(_error!));
    final editable=widget.enabled&&!_busy&&!_confirming&&_pending==null&&_state?.canEdit==true&&_active;
    return Card(child:ExpansionTile(title:const Text('給与への適用月'),subtitle:const Text('保存済みの追加手当を給与へ反映'),children:[ConstrainedBox(constraints:const BoxConstraints(maxHeight:120),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      if(_error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(_error!)),
      if(_showApplicationSummary&&_state?.applicationSummary!=null)Padding(padding:const EdgeInsets.all(12),child:Text(_state!.applicationSummary!.message)),
      Row(children:[if(_state!=null)Expanded(child:Padding(padding:const EdgeInsets.only(left:12),child:DropdownButton<String>(key:const ValueKey('common-publication-type'),value:_type,isExpanded:true,items:[for(final type in ['daily','hourly','monthly'])DropdownMenuItem(value:type,child:Text(_typeLabel(type)))],onChanged:editable?(value)=>setState((){_type=value!;_hideApplicationSummary();}):null))),IconButton(key:const ValueKey('common-publication-previous'),onPressed:editable&&_month.isAfter(_currentMonth)?()=>setState((){_month=DateTime(_month.year,_month.month-1);_hideApplicationSummary();}):null,icon:const Icon(Icons.chevron_left)),Text('${_month.year}/${_month.month}'),IconButton(key:const ValueKey('common-publication-next'),onPressed:editable?()=>setState((){_month=DateTime(_month.year,_month.month+1);_hideApplicationSummary();}):null,icon:const Icon(Icons.chevron_right))]),
      if(_pending!=null)TextButton(key:const ValueKey('common-publication-reconcile'),onPressed:_busy||!widget.canReconcile||!_active?null:_applyPending,child:const Text('適用結果を確認'))
      else if(_state?.canEdit==true)TextButton(key:const ValueKey('common-publication-apply'),onPressed:editable?_start:null,child:const Text('保存済み手当を適用')),
      if(_error!=null&&_pending==null)TextButton(onPressed:_busy||!_active?null:_load,child:const Text('再読み込み')),
      if(_busy)const LinearProgressIndicator(),
      for(final entry in (_state?.entries??const <Map<String,dynamic>>[]).take(5))ListTile(dense:true,title:Text('${_typeLabel(entry['payroll_type'] as String)}  ${(entry['starts_on'] as String).substring(0,7)}  適用登録済み')),
    ]))) ]));
  }
}
