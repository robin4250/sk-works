import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';
import 'trade_document_attachment_repository.dart';
import 'trade_document_date_defaults.dart';

/// One explicit monthly save; never writes or approves the source financial document.
class TradeDocumentAttachmentEditorPage extends StatefulWidget {
  const TradeDocumentAttachmentEditorPage({super.key,required this.subjectKind,
    required this.subjectId,required this.sourceRevision});
  final String subjectKind,subjectId,sourceRevision;
  @override State<TradeDocumentAttachmentEditorPage> createState()=>_EditorState();
}
class _EditorState extends State<TradeDocumentAttachmentEditorPage> {
  final _repo=TradeDocumentAttachmentRepository.maybeCreate();
  final _fields=<String,TextEditingController>{};
  Map<String,dynamic>? _workspace;
  Map<String,dynamic> _payload={};
  String? _error;
  bool _saving=false;
  int _version=0;
  String? _actor;
  StreamSubscription<dynamic>? _subscription;
  bool get _sameActor=>_actor!=null&&SupabaseBackend.isInitialized&&SupabaseBackend.client.auth.currentUser?.id==_actor;
  bool _revoked=false;
  bool get _canEdit=>!_revoked&&_sameActor&&(_workspace?['can_manage']==true)&&
    !(_version>0&&_workspace?['source_locked']==true)&&_workspace?['source_blocked']!=true;
  bool get _order=>widget.subjectKind=='payment_certificate';
  @override void initState(){super.initState();
    _actor=SupabaseBackend.isInitialized?SupabaseBackend.client.auth.currentUser?.id:null;
    if(SupabaseBackend.isInitialized) {
      _subscription=SupabaseBackend.client.auth.onAuthStateChange.listen((_) {
      if(!_sameActor&&!_revoked&&mounted) setState(() {_revoked=true;_payload={};_error='ログイン情報が変わりました。開き直してください。';});
    },onError:(_){if(mounted)setState(()=>_revoked=true);});
    }
    _load();
  }
  Future<void> _load() async {
    try {
      if(_repo==null) throw StateError('ログインが必要です。');
      final data=await _repo.loadWorkspace(subjectKind:widget.subjectKind,subjectId:widget.subjectId,sourceRevision:widget.sourceRevision);
      if(!mounted||!_sameActor||_revoked)return;
      final saved=data['attachment'];
      _payload=Map<String,dynamic>.from(saved is Map&&data['source_changed']!=true?saved['payload'] as Map:data['defaults'] as Map);
      _version=saved is Map?saved['version'] as int:0;
      if(_version==0||data['source_changed']==true){
        final defaults=data['template'] is Map?Map<String,dynamic>.from(data['template'] as Map):<String,dynamic>{};
        for(final entry in defaults.entries){_payload[entry.key]=entry.value;}
        _payload.putIfAbsent('intro_text',()=> '発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。');
        _payload.putIfAbsent('acceptance_text',()=> '乙は、貴殿から受領した{order_date}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。');
        _payload.putIfAbsent('payment_conditions',()=> '工事完了確認後、乙の指定口座に振り込む。');
        _payload.putIfAbsent('notes',()=> '');
      }
      if (_version == 0) {
        _payload.addAll(tradeDocumentDateDefaults(_payload['month'].toString()));
        if (_order) {
          _payload['work_name'] = '鳶工・安全設備・足場組み立て解体作業';
          if (_payload['payment_conditions'] == null ||
              _payload['payment_conditions'].toString().trim().isEmpty ||
              _payload['payment_conditions'] == '工事完了確認後、乙の指定口座に振り込む。') {
            _payload['payment_conditions'] = tradeDocumentDefaultPaymentConditions(_payload['month'].toString());
          }
          if ((_payload['notes']?.toString().trim() ?? '').isEmpty) {
            _payload['notes'] = '・本工事は建設業許可を必要としない軽微な工事である。\n・乙は、工事中の事故等について一切の責任を負う。';
          }
        } else {
          _payload['issue_date'] = DateTime.now().toUtc().add(const Duration(hours: 9))
              .toIso8601String().substring(0, 10);
        }
      }
      for(final key in ['issue_date','order_date','work_name','work_address','period_start','period_end','payment_conditions','notes','tax_amount_yen','total_amount_yen','intro_text','acceptance_text']){
        _fields[key]=TextEditingController(text:_payload[key]?.toString()??'');
      }
      for(final party in ['issuer','counterparty']){
        final values=_payload[party] as Map? ?? {};
        for(final key in ['name','address','corporate_number','representative_name']){
          _fields['$party.$key']=TextEditingController(text:values[key]?.toString()??'');
        }
      }
      setState(()=>_workspace=data);
    } catch(e){if(mounted)setState(()=>_error=e.toString());}
  }
  @override void dispose(){_subscription?.cancel();for(final c in _fields.values){c.dispose();}super.dispose();}
  Widget _input(String key,String label,{int max=240,int lines=1,bool readOnly=false})=>Padding(
    padding:const EdgeInsets.only(bottom:12),child:TextField(controller:_fields[key],
      enabled:_canEdit,readOnly:readOnly,maxLength:max,maxLines:lines,
      decoration:InputDecoration(labelText:label,border:const OutlineInputBorder(),counterText:'')));
  Future<void> _save() async {
    if(!_canEdit||_saving)return;
    setState(()=>_saving=true);
    try {
      final value=Map<String,dynamic>.from(_payload);
      for(final entry in _fields.entries){
        if(entry.key.contains('.'))continue;
        value[entry.key]=entry.key.endsWith('_yen')?int.tryParse(entry.value.text):entry.value.text.trim();
      }
      for(final party in ['issuer','counterparty']){
        value[party]={for(final key in ['name','address','corporate_number','representative_name'])key:_fields['$party.$key']!.text.trim()};
      }
      if(!_order){value['acceptance_text']=(value['acceptance_text'] as String).replaceAll('{order_date}',tradeDocumentJapaneseDate(value['order_date'].toString()));}
      await _repo!.save(subjectKind:widget.subjectKind,subjectId:widget.subjectId,
        sourceRevision:widget.sourceRevision,expectedVersion:_version,payload:value);
      if(!mounted||!_sameActor||_revoked)return;
      Navigator.of(context).pop(true);
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_saving=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_order?'月次 注文書':'月次 注文請書')),
    body:_workspace==null?Center(child:Text(_error??'読み込み中…')):_revoked?const Center(child:Text('開き直してください。')):
    ListView(padding:const EdgeInsets.all(16),children:[
      Text('対象月：${_payload['month']}  ／ ${_version==0?'未添付':'保存済み 第$_version版'}',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:8),
      if(_workspace?['source_changed']==true)const Text('元の帳票が更新されています。旧版の別添は保持しています。新しい当月の内容を確認して保存し直してください。'),
      const Text('この月の短期工事契約の別添です。初期値は工期が対象月の1日〜末日、契約日は前月15日です。日付は変更できます。保存して添付すると通常のPDFの2ページ目に入ります。元の帳票の承認・再発行は行いません。'),
      if(_workspace?['source_blocked']==true)const Text('元帳票の計算条件が未確定です。先に元帳票を確認してください。'),
      if(!_canEdit)const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('閲覧のみ（確定済みの別添は変更できません）')),
      const SizedBox(height:16),
      _input('issue_date',_order?'発行日（YYYY-MM-DD）':'承諾日（YYYY-MM-DD）',max:10),
      if(!_order)_input('order_date','受領注文書日（YYYY-MM-DD）',max:10),
      if(_order)...[
        _input('intro_text','冒頭文',max:400,lines:3),
        _input('work_name','件名'),_input('work_address','工事場所'),
        _input('period_start','工期開始（YYYY-MM-DD）',max:10),_input('period_end','工期終了（YYYY-MM-DD）',max:10),
        _input('total_amount_yen','当月の請負代金（税込・円）',max:10,readOnly:true),
        _input('tax_amount_yen','うち消費税等（円・要確認）',max:10),
        _input('payment_conditions','支払条件（期限も入力）',max:400,lines:4),
      ]else _input('acceptance_text','承諾文（{order_date} は注文書日に置換）',max:400,lines:4),
      if(_order)OutlinedButton.icon(onPressed:_canEdit&&!_saving?(){
        _fields['notes']!.text='・本工事は建設業許可を必要としない軽微な工事である。\n・乙は、工事中の事故等について一切の責任を負う。';
      }:null,icon:const Icon(Icons.edit_note),label:const Text('見本の特記事項を入れる')),
      _input('notes','その他特記事項（任意）',max:600,lines:5),
      const Text('特記事項は実際の合意内容に合わせて編集できます。'),
      for(final party in ['issuer','counterparty'])...[
        const SizedBox(height:16),Text(party=='issuer'?(_order?'甲・発注者（自社）':'乙・受注者（自社）'):(_order?'乙・受注者（下請け会社）':'甲・発注者（請求先）'),style:Theme.of(context).textTheme.titleMedium),
        _input('$party.name','社名',max:120,readOnly:party=='issuer'),
        if(_order||party=='issuer')...[_input('$party.address','住所（任意）',max:240,lines:2),
        _input('$party.corporate_number','法人番号（任意・13桁）',max:13),
        _input('$party.representative_name','代表者名（任意）',max:80)],
      ],
      const Text('角印は会社で設定済みの印影・表示設定を保存します。'),
      if(_error!=null)Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const SizedBox(height:16),FilledButton(onPressed:_canEdit&&!_saving?_save:null,child:Text(_saving?'保存中…':'保存して添付')),
    ]));
}
