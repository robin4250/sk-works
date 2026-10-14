import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/supabase_backend.dart';

class TradeDocumentTemplateSettingsButton extends StatelessWidget {
  const TradeDocumentTemplateSettingsButton({super.key,required this.subjectKind});
  final String subjectKind;
  @override Widget build(BuildContext context)=>ListTile(
    leading:const Icon(Icons.description_outlined),
    title:Text(subjectKind=='invoice'?'注文請書の設定':'注文書の設定'),
    subtitle:const Text('毎月の短期契約書・既定の文面'),
    trailing:const Icon(Icons.chevron_right),
    onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>TradeDocumentTemplateSettingsPage(subjectKind:subjectKind))));
}
class TradeDocumentTemplateSettingsPage extends StatefulWidget {
 const TradeDocumentTemplateSettingsPage({super.key,required this.subjectKind});
 final String subjectKind;
 @override State<TradeDocumentTemplateSettingsPage> createState()=>_TemplateState();
}
class _TemplateState extends State<TradeDocumentTemplateSettingsPage> {
 final _controllers=<String,TextEditingController>{};
 String? _company,_actor,_error; int _version=0;bool _ready=false,_canManage=false,_saving=false,_revoked=false;
 StreamSubscription<dynamic>? _subscription;
 bool get _sameActor=>SupabaseBackend.isInitialized&&SupabaseBackend.client.auth.currentUser?.id==_actor;
 @override void initState(){super.initState();_load();}
 Future<void> _load() async {
  try{
   if(!SupabaseBackend.isInitialized)throw StateError('ログインが必要です。');
   final c=SupabaseBackend.client;_actor=c.auth.currentUser?.id;
   if(_actor==null)throw StateError('ログインが必要です。');
   _subscription=c.auth.onAuthStateChange.listen((_){if(!_sameActor&&mounted)setState((){_revoked=true;_canManage=false;});},onError:(_){if(mounted)setState(()=>_revoked=true);});
   final rows=await c.from('company_members').select('company_id').eq('user_id',_actor!);
   if(rows.length!=1)throw StateError('対象の会社を一意に確認できません。');
   _company=rows.first['company_id'].toString();
   final data=await c.rpc('trade_document_template',params:{'p_kind':widget.subjectKind,'p_company':_company});
   if(!mounted||!_sameActor||_revoked)return;
   final payload=data['payload'] as Map;
   final defaults={'intro_text':'発注者（以下「甲」という）は、受注者（以下「乙」という）に対し、下記の通り工事を発注します。',
    'acceptance_text':'乙は、貴殿から受領した{order_date}付の注文書記載の条件通り、本工事を請け負うことを承諾いたします。',
    'payment_conditions':'工事完了確認後、乙の指定口座に振り込む。','notes':''};
   for(final key in defaults.keys){_controllers[key]=TextEditingController(text:payload[key]?.toString()??defaults[key]);}
   setState((){_version=data['version'] as int;_canManage=data['can_manage']==true;_ready=true;});
  }catch(e){if(mounted)setState(()=>_error=e.toString());}
 }
 Future<void> _save()async{
  if(!_sameActor||_revoked||!_canManage||_saving)return;setState(()=>_saving=true);
  try{await SupabaseBackend.client.rpc('trade_document_template',params:{'p_kind':widget.subjectKind,'p_company':_company,
   'p_expected_version':_version,'p_payload':{for(final entry in _controllers.entries)entry.key:entry.value.text.trim()}});
   if(mounted&&_sameActor&&!_revoked)Navigator.of(context).pop();
  }catch(e){if(mounted)setState(()=>_error=e.toString());}finally{if(mounted)setState(()=>_saving=false);}
 }
 @override void dispose(){_subscription?.cancel();for(final c in _controllers.values){c.dispose();}super.dispose();}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.subjectKind=='invoice'?'注文請書の設定':'注文書の設定')),
 body:!_ready?Center(child:Text(_error??'読み込み中…')):_revoked?const Center(child:Text('開き直してください。')):
 ListView(padding:const EdgeInsets.all(16),children:[
 const Text('新しく作る月次別添の既定値です。保存済みの注文書・注文請書には変更を反映しません。'),const SizedBox(height:16),
 if(widget.subjectKind=='payment_certificate')OutlinedButton.icon(
  onPressed:_canManage&&!_saving?(){_controllers['notes']!.text='・本工事は建設業許可を必要としない軽微な工事である。\n・乙は、工事中の事故等について一切の責任を負う。';}:null,
  icon:const Icon(Icons.edit_note),label:const Text('見本の特記事項を入れる')),

 for(final key in widget.subjectKind=='invoice'?['acceptance_text','notes']:['intro_text','payment_conditions','notes'])
 Padding(padding:const EdgeInsets.only(bottom:16),child:TextField(controller:_controllers[key],enabled:_canManage&&!_saving,maxLines:5,
 maxLength:key=='notes'?600:400,decoration:InputDecoration(border:const OutlineInputBorder(),labelText:{'intro_text':'注文書の冒頭文','acceptance_text':'承諾文（{order_date}を注文書日に置換）','payment_conditions':'支払条件','notes':'その他特記事項'}[key]))),
 if(_error!=null)Text(_error!),FilledButton(onPressed:_canManage&&!_saving?_save:null,child:const Text('設定を保存'))]));
}
