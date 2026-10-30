import '../../domain/trade_document_terms_snapshot.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/scheduler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/trade_document_form_draft.dart';
import '../../domain/trade_document_editor_payload.dart';
import 'trade_document_form_session.dart';
import 'trade_document_form_renderer.dart';
import 'trade_document_touch_editor_page.dart';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_attachment_repository.dart';
import 'r18_defaults.dart';
import 'r33_input.dart';

/// One explicit monthly save; never writes or approves the source financial document.
class TradeDocumentAttachmentEditorPage extends StatefulWidget {
  const TradeDocumentAttachmentEditorPage({super.key,required this.subjectKind,
    required this.subjectId,required this.sourceRevision,this.initialInput,this.clientOverride,this.repositoryFactory});
  final String subjectKind,subjectId,sourceRevision;
  final R33Input? initialInput;
  final SupabaseClient? clientOverride;
  final TradeDocumentAttachmentRepository Function(SupabaseClient,TradeDocumentFormSession)? repositoryFactory;
  @override State<TradeDocumentAttachmentEditorPage> createState()=>_EditorState();
}
class _EditorState extends State<TradeDocumentAttachmentEditorPage> {
  TradeDocumentAttachmentRepository? _repo;
  TradeDocumentFormSession? _scope;
  late final String _entryTarget;
  bool _typedLaunched=false,_saveUncertain=false;
  bool get _typed=>_payload.containsKey('contract_terms');
  String get _target=>'${widget.subjectKind}/${widget.subjectId}/${widget.sourceRevision}';
  final _fields=<String,TextEditingController>{};
  Map<String,dynamic>? _workspace;
  Map<String,dynamic> _payload={};
  String? _error;
  bool _saving=false;
  int _version=0;
  String? _actor;
  bool _revoked=false;
  bool get _canEdit=>!_revoked&&!_saveUncertain&&(_scope?.isCurrent??false)&&(_workspace?['can_manage']==true)&&
    !(_version>0&&_workspace?['source_locked']==true)&&_workspace?['source_blocked']!=true;
  bool get _order=>widget.subjectKind=='payment_certificate';
  @override void initState(){super.initState();_entryTarget=_target;
    try {
      final client=widget.clientOverride??(SupabaseBackend.isInitialized?SupabaseBackend.client:null);
      if(client==null)throw StateError('ログインが必要です。');
      _actor=client.auth.currentUser?.id;
      final scope=TradeDocumentFormSession(client,target:_entryTarget,currentTarget:()=>_target);
      _scope=scope;scope.addListener(_scopeChanged);
      _repo=widget.repositoryFactory?.call(client,scope)??TradeDocumentAttachmentRepository(client,session:scope);
      if(!_repo!.isBoundTo(scope))throw StateError('書類操作の接続を確認できません。');
      _load();
    }catch(error){_error=error.toString();_retire();}
  }
  void _requireScope(){
    if(!mounted||_revoked||_target!=_entryTarget)throw StateError('書類を開き直してください。');
    _scope!.requireScope();
  }
  void _scopeChanged(){if(!(_scope?.isCurrent??false))_retire();}
  void _retire(){
    if(_revoked)return;_revoked=true;_payload={};_workspace=null;
    for(final controller in _fields.values){controller.clear();}
    if(!mounted)return;
    if(SchedulerBinding.instance.schedulerPhase==SchedulerPhase.persistentCallbacks){
      WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)setState((){});});
    }else{setState((){});}
  }
  @override void didUpdateWidget(covariant TradeDocumentAttachmentEditorPage old){super.didUpdateWidget(old);if(_target!=_entryTarget)_retire();}
  Future<void> _load() async {
    try {
      if(_repo==null) throw StateError('ログインが必要です。');
      await _scope!.ready();_requireScope();
      final data=await _repo!.loadWorkspace(subjectKind:widget.subjectKind,subjectId:widget.subjectId,sourceRevision:widget.sourceRevision);
      _requireScope();
      final saved=data['attachment'];
      _payload=Map<String,dynamic>.from(saved is Map&&data['source_changed']!=true?saved['payload'] as Map:data['defaults'] as Map);
      _version=saved is Map?saved['version'] as int:0;
      if(_version==0||data['source_changed']==true){
        final defaults=data['template'] is Map?Map<String,dynamic>.from(data['template'] as Map):<String,dynamic>{};
        for(final key in ['intro_text','acceptance_text','payment_conditions','notes','work_name','work_address']){
          final value=defaults[key];
          if(value is String&&(!{'work_name','work_address'}.contains(key)||value.trim().isNotEmpty))_payload[key]=value;
        }
        _payload.putIfAbsent('intro_text',()=> '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。');
        _payload.putIfAbsent('acceptance_text',()=> '乙は、貴殿から受領した{order_date}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。');
        _payload.putIfAbsent('payment_conditions',()=> '工事完了確認後、乙の指定口座に振り込む。');
        _payload.putIfAbsent('notes',()=> '');
      }
      // A fresh invoice appendix must not inherit its parent invoice date.
      if (saved is! Map && widget.subjectKind == 'invoice') {
        _payload.remove('issue_date');
      }
      // Initial defaults remain local before the explicit save.
      _payload = r18InitialValues(payload: _payload,
        sourceDefaults: Map<String, dynamic>.from(data['defaults'] as Map),
        hasSavedAttachment: saved is Map, subjectKind: widget.subjectKind);
      if(saved is! Map && data['source_locked']==false) _payload=TradeDocumentTermsSnapshot.initialize(_payload);
      _payload = preserveSavedTradeDocumentFields(payload:_payload,workspace:data,subjectKind:widget.subjectKind,subjectId:widget.subjectId);
      _payload = widget.initialInput?.apply(payload: _payload, workspace: data,
        actor: _actor, subjectKind: widget.subjectKind, subject: widget.subjectId,
        revision: widget.sourceRevision) ?? _payload;
      for(final key in ['issue_date','order_date','work_name','work_address','period_start','period_end','payment_conditions','notes','tax_amount_yen','total_amount_yen','intro_text','acceptance_text']){
        _fields[key]=TextEditingController(text:_payload[key]?.toString()??'');
      }
      for(final party in ['issuer','counterparty']){
        final values=_payload[party] as Map? ?? {};
        for(final key in ['name','address','corporate_number','representative_name']){
          _fields['$party.$key']=TextEditingController(text:values[key]?.toString()??'');
        }
      }
      _requireScope();setState(()=>_workspace=data);
      if(_typed&&_canEdit){WidgetsBinding.instance.addPostFrameCallback((_){if(mounted&&!_revoked)unawaited(_openTyped());});}
    } catch(e){if(mounted)setState(()=>_error=e.toString());}
  }
  @override void dispose(){_scope?.removeListener(_scopeChanged);_scope?.dispose();for(final c in _fields.values){c.dispose();}super.dispose();}
  Future<Uint8List> _preview(Map<String,dynamic> payload)async{
    _requireScope();final bytes=await TradeDocumentFormRenderer.canonical(payload);_requireScope();return bytes;
  }
  Future<void> _saveTyped(Map<String,dynamic> payload)async{
    _requireScope();if(!_canEdit||_saving)throw StateError('保存状態を確認してください。');
    _saving=true;
    try{
      final saved=await _repo!.save(subjectKind:widget.subjectKind,subjectId:widget.subjectId,
        sourceRevision:widget.sourceRevision,expectedVersion:_version,payload:payload);
      _requireScope();_payload=saved.payload;_version=saved.version;
    }catch(_){_saveUncertain=true;rethrow;}finally{_saving=false;}
  }
  Future<TradeDocumentFormDraft> _refreshOwnCompany(TradeDocumentFormDraft current)async{
    _requireScope();if(!_canEdit)throw StateError('この書類は変更できません。');
    final fresh=await _repo!.loadWorkspace(subjectKind:widget.subjectKind,subjectId:widget.subjectId,sourceRevision:widget.sourceRevision);
    _requireScope();
    final attachment=fresh['attachment'];final version=attachment is Map?attachment['version']:0;
    if(version!=_version||fresh['company_id']!=_workspace?['company_id']||fresh['source_revision']!=_workspace?['source_revision']||
      fresh['source_changed']==true||fresh['source_locked']==true||fresh['source_blocked']==true||fresh['can_manage']!=true||fresh['form_fields_schema_version']!=2) {
      throw StateError('書類や会社情報の状態が変わりました。開き直してください。');
    }
    final issuer=(fresh['defaults'] as Map?)?['issuer'];final payload=current.payload;final previous=payload['issuer'] as Map;
    if(issuer is! Map||issuer['name']!=previous['name'])throw StateError('登録会社を確認できません。');
    final next=Map<String,dynamic>.from(previous);
    for(final key in ['phone','fax','representative_name']) {
      final value=issuer[key];if(value is! String||value.runes.length>(key=='representative_name'?80:40))throw StateError('会社の連絡先を確認できません。');
      next[key]=value;
    }
    payload['issuer']=next;
    return TradeDocumentFormDraft.fromPayload(payload,allowAmountEditing:false);
  }
  Future<void> _openTyped()async{
    if(_typedLaunched||!_canEdit)return;
    try{
      _requireScope();final draft=TradeDocumentFormDraft.fromPayload(_payload,allowAmountEditing:false,initializeDefaults:_version==0&&_workspace?['source_locked']==false,initializeExtendedFields:_version==0&&_workspace?['source_locked']==false&&_workspace?['form_fields_schema_version']==2);
      _typedLaunched=true;
      final saved=await Navigator.of(context).push<bool>(MaterialPageRoute(builder:(_)=>TradeDocumentTouchEditorPage(
        initial:draft,allowExtendedFields:_workspace?['form_fields_schema_version']==2,onRefreshOwnCompany:_workspace?['form_fields_schema_version']==2?_refreshOwnCompany:null,requireScope:_requireScope,scopeChanges:_scope,canEdit:true,buildPreview:_preview,onSave:_saveTyped)));
      if(!mounted)return;_requireScope();
      if(saved==true&&ModalRoute.of(context)?.isCurrent==true){Navigator.of(context).pop(true);}
    }catch(error){if(mounted&&!_revoked)setState(()=>_error=error.toString());}
    finally{_typedLaunched=false;if(mounted&&!_revoked)setState((){});}
  }
  Widget _input(String key,String label,{int max=240,int lines=1,bool readOnly=false})=>Padding(
    padding:const EdgeInsets.only(bottom:12),child:TextField(controller:_fields[key],
      enabled:_canEdit,readOnly:readOnly,maxLength:max,maxLines:lines,
      decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),counterText:'')));
  Future<void> _save() async {
    if(!_canEdit||_saving||_saveUncertain)return;
    _requireScope();
    setState(()=>_saving=true);
    try {
      final value=Map<String,dynamic>.from(_payload);
      for(final entry in _fields.entries){
        if(entry.key.contains('.')||entry.key.endsWith('_yen'))continue;
        if(!_payload.containsKey(entry.key)&&entry.value.text.trim().isEmpty)continue;
        value[entry.key]=entry.value.text.trim();
      }
      if(!_order){value['acceptance_text']=(value['acceptance_text'] as String).replaceAll('{order_date}',value['order_date'].toString());}
      final saved=await _repo!.save(subjectKind:widget.subjectKind,subjectId:widget.subjectId,
        sourceRevision:widget.sourceRevision,expectedVersion:_version,payload:value);
      if(!mounted)return;
      _requireScope();_payload=saved.payload;_version=saved.version;
      if(ModalRoute.of(context)?.isCurrent==true)Navigator.of(context).pop(true);
    }catch(e){_saveUncertain=true;if(mounted&&!_revoked)setState(()=>_error='保存結果を確認できません。元の画面で登録状態を確認してください。');}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_order?'月次 注文書':'月次 注文請書')),
    body:_revoked?Center(child:Text(_error??'開き直してください。')):_workspace==null?Center(child:Text(_error??'読み込み中…')):_typed?Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(_saveUncertain?'保存結果を元の画面で確認してください。':_error??'保存した書類を確認します。'),
      if(_canEdit)FilledButton(onPressed:_typedLaunched?null:_openTyped,child:const Text('入力画面を開く')),
      if(!_canEdit)const Text('閲覧のみ（内容は変更できません）'),
    ])):
    ListView(padding:const EdgeInsets.all(16),children:[
      Text('対象月：${_payload['month']}  ／ ${_version==0?'未添付':'保存済み 第$_version版'}',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      if(_workspace?['source_changed']==true)const Text('元の帳票が更新されています。旧版の別添は保持しています。新しい当月の内容を確認して保存し直してください。'),
      const Text('この月の短期工事契約の別添です。下書きのPDF出力時に注文書・注文請書を自動生成して添付します。この画面では内容を確認・編集し、保存した内容を優先します。確定済み帳票に別添がない場合は、内容を確認して保存してください。元の帳票の承認・再発行は行いません。'),
      if(_workspace?['source_blocked']==true)const Text('元帳票の計算条件が未確定です。先に元帳票を確認してください。'),
      if(!_canEdit)const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('閲覧のみ（確定済みの別添は変更できません）')),
      const SizedBox(height:16),
      _input('issue_date',_order?'発行日（YYYY-MM-DD）':'承諾日（YYYY-MM-DD）',max:10),
      if(!_order)_input('order_date','受領注文書日（YYYY-MM-DD）',max:10),
      if(_order)...[
        _input('intro_text','冒頭文',max:400,lines:3),
        _input('work_name','工事名'),_input('work_address','工事場所'),
        _input('period_start','工期開始（YYYY-MM-DD）',max:10),_input('period_end','工期終了（YYYY-MM-DD）',max:10),
        _input('total_amount_yen','当月の請負代金（税込・円）',max:10,readOnly:true),
        _input('tax_amount_yen','うち消費税等（円・要確認）',max:10,readOnly:true),
        _input('payment_conditions','支払条件（期限も入力）',max:400,lines:4),
      ]else ...[
        _input('work_name','工事名（請求書の件名）'),
        _input('acceptance_text','承諾文（{order_date} は注文書日に置換）',max:400,lines:4),
      ],
      if(_order)OutlinedButton.icon(onPressed:_canEdit&&!_saving?(){
        _fields['notes']!.text='・本工事は建設業許可を必要としない軽微な工事である。\n・乙は、工事中の事故等について一切の責任を負う。';
      }:null,icon:const Icon(Icons.edit_note),label:const Text('見本の特記事項を入れる')),
      _input('notes','その他特記事項（任意）',max:600,lines:5),
      const Text('特記事項は実際の合意内容に合わせて編集できます。'),
      for(final party in ['issuer','counterparty'])...[
        const SizedBox(height:16),Text(party=='issuer'?(_order?'甲・発注者（自社）':'乙・受注者（自社）'):(_order?'乙・受注者（下請け会社）':'甲・発注者（請求先）'),style:Theme.of(context).textTheme.titleMedium),
        _input('$party.name','社名',max:120,readOnly:true),
        if(_order||party=='issuer')...[_input('$party.address','住所（任意）',max:240,lines:2,readOnly:true),
        _input('$party.corporate_number','法人番号（任意・13桁）',max:13,readOnly:true),
        _input('$party.representative_name','代表者名（任意）',max:80,readOnly:true)],
      ],
      const Text('角印は会社で設定済みの印影・表示設定を保存します。'),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const SizedBox(height:16),FilledButton(onPressed:_canEdit&&!_saving?_save:null,child:Text(_saving?'保存中…':'保存して添付')),
    ]));
}


