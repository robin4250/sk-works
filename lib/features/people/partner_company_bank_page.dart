import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/partner_company_bank_account.dart';
import 'partner_company_bank_repository.dart';
import 'people_cloud_repository.dart';

/// Separate financial page; no bank values are fetched into the People list.
class PartnerCompanyBankPage extends StatefulWidget {
 const PartnerCompanyBankPage({super.key,required this.privacySession,required this.expectedCompany,
  required this.partnerCompanyId,required this.partnerName,this.repositoryOverride});
 final PersonnelPrivacySession privacySession;
 final String expectedCompany,partnerCompanyId,partnerName;
 @visibleForTesting final PartnerCompanyBankRepository? repositoryOverride;
 @override State<PartnerCompanyBankPage> createState()=>_PartnerCompanyBankPageState();
}
class _PartnerCompanyBankPageState extends State<PartnerCompanyBankPage> with WidgetsBindingObserver {
 final _privateNavigator=GlobalKey<NavigatorState>();
 final _bank=TextEditingController(),_branch=TextEditingController(),_number=TextEditingController(),_holder=TextEditingController();
 PartnerCompanyBankRepository? _repository;
 PartnerCompanyBankWorkspace? _workspace;
 String _type='普通';bool _busy=true,_blocked=false,_uncertain=false;String? _error;
 int _generation=0;int? _privacyEpoch;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);widget.privacySession.addListener(_privacyChanged);unawaited(_load());}
 @override void didUpdateWidget(covariant PartnerCompanyBankPage oldWidget){
  super.didUpdateWidget(oldWidget);
  if(!identical(oldWidget.privacySession,widget.privacySession)){oldWidget.privacySession.removeListener(_privacyChanged);widget.privacySession.addListener(_privacyChanged);}
  if(oldWidget.expectedCompany!=widget.expectedCompany||oldWidget.partnerCompanyId!=widget.partnerCompanyId||!identical(oldWidget.privacySession,widget.privacySession)){_block();}
 }
 void _privacyChanged(){final scope=widget.privacySession;
  if(scope.revoked||!scope.active||scope.snapshot?.canManage==false||(_privacyEpoch!=null&&(_privacyEpoch!=scope.epoch||scope.snapshot==null))){_block();}
 }
 void _ownerChanged(){if(_repository?.isCurrent!=true){_block();}}
 void _block(){if(_blocked||!mounted){return;}_generation++;setState((){_blocked=true;_busy=false;_workspace=null;_bank.clear();_branch.clear();_number.clear();_holder.clear();});}
 @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.paused||state==AppLifecycleState.hidden||state==AppLifecycleState.detached){_block();}}
 bool _live(int generation)=>mounted&&!_blocked&&generation==_generation;
 Future<void> _load() async {
  if(_blocked){return;}final generation=++_generation;setState(()=>_busy=true);
  try{
   if(_repository==null){_repository=widget.repositoryOverride??PartnerCompanyBankRepository.maybeCreate(privacySession:widget.privacySession,expectedCompany:widget.expectedCompany,partnerCompanyId:widget.partnerCompanyId);_repository?.addListener(_ownerChanged);}
   final repository=_repository;if(repository==null){throw const PersonnelScopeChanged();}
   final value=await repository.load();if(!_live(generation)){return;}
   setState((){_privacyEpoch??=widget.privacySession.epoch;_workspace=value;_uncertain=false;_error=null;
    _bank.text=value.bank?.bankName??'';_branch.text=value.bank?.branchName??'';_number.text=value.bank?.accountNumber??'';_holder.text=value.bank?.accountHolder??'';_type=value.bank?.accountType??'普通';});
  }catch(_){if(_live(generation)){setState(()=>_error='銀行口座情報を確認できません。権限・登録状態を確認してください。');}}
  finally{if(_live(generation)){setState(()=>_busy=false);}}
 }
 Future<void> _save() async {
  final workspace=_workspace;if(_busy||_blocked||_uncertain||workspace==null||!workspace.available){return;}
  PartnerCompanyBankAccount bank;
  try{bank=PartnerCompanyBankAccount(companyId:widget.expectedCompany,partnerCompanyId:widget.partnerCompanyId,bankVersion:workspace.version+1,
    bankName:_bank.text.trim(),branchName:_branch.text.trim(),accountType:_type,accountNumber:_number.text,accountHolder:_holder.text.trim());}
  on FormatException catch(error){setState(()=>_error=error.message);return;}
  final generation=_generation;setState(()=>_busy=true);
  try{await _repository!.save(expectedVersion:workspace.version,bank:bank);if(!mounted||!_live(generation)){return;}Navigator.of(context).pop(true);}
  catch(_){if(_live(generation)){setState((){_uncertain=true;_error='保存結果を確認できません。同じ送信を繰り返さず、再読み込みで現在の登録を確認してください。';});}}
  finally{if(_live(generation)){setState(()=>_busy=false);}}
 }
 @override void dispose(){_generation++;WidgetsBinding.instance.removeObserver(this);widget.privacySession.removeListener(_privacyChanged);_repository?.removeListener(_ownerChanged);_repository?.dispose();for(final c in [_bank,_branch,_number,_holder]){c.dispose();}super.dispose();}
 Widget _field(String label,TextEditingController controller,{bool number=false,int max=100})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:controller,enabled:!_busy&&!_uncertain,
  maxLength:max,keyboardType:number?TextInputType.number:null,inputFormatters:number?[FilteringTextInputFormatter.digitsOnly,LengthLimitingTextInputFormatter(7)]:null,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
 @override Widget build(BuildContext context){
  if(_blocked){return Scaffold(appBar:AppBar(title:const Text('協力会社の銀行口座')),body:const Center(child:Text('表示を停止しました。会社詳細から開き直してください。')));}
  return Navigator(key:_privateNavigator,pages:[MaterialPage<void>(child:Builder(builder:(innerContext)=>Scaffold(
   appBar:AppBar(title:const Text('協力会社の銀行口座'),leading:BackButton(onPressed:()=>Navigator.of(context).pop(false))),
   body:ListView(padding:const EdgeInsets.all(16),children:[Text(widget.partnerName),
    const Text('この会社への振込先です。社員本人の給与口座ではありません。変更前の登録版は保持され、既発行の注文書は変更しません。'),
    if(_busy)const LinearProgressIndicator(),if(_error!=null)Text(_error!),
    if(_workspace?.available==false)const Text('協力会社の銀行口座登録は準備中です。'),
    if(_workspace?.available==true)...[
     Text('登録版：${_workspace!.version}'),_field('銀行名',_bank),_field('支店名',_branch),
     DropdownButtonFormField<String>(key:ValueKey('${_workspace?.version}:$_type'),initialValue:_type,items:[for(final type in ['普通','当座','貯蓄'])DropdownMenuItem(value:type,child:Text(type))],onChanged:_busy||_uncertain?null:(value){if(value!=null){setState(()=>_type=value);}},decoration:const InputDecoration(labelText:'口座種別')),
     const SizedBox(height:12),_field('口座番号（半角7桁）',_number,number:true,max:7),_field('口座名義',_holder,max:120),
     FilledButton(onPressed:_busy||_uncertain?null:_save,child:const Text('この協力会社の口座を保存')),
    ],
    OutlinedButton(onPressed:_busy?null:_load,child:const Text('現在の登録を再読み込み')),
    TextButton(onPressed:()=>Navigator.of(context).pop(false),child:const Text('キャンセル')),
   ]))))],onDidRemovePage:(_){});
 }
}
