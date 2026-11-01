import 'dart:math';
import 'package:flutter/material.dart';
import '../auth/operation_reauthentication_repository.dart';
import '../people/own_bank_account_repository.dart';
import '../settings/master_feature_proof_dialog.dart';
import 'personal_details_repository.dart';

/// Personal UID data only. Never imports company documents, worker bank or family DOB.
class PersonalDetailsPage extends StatefulWidget {
 const PersonalDetailsPage({super.key,this.gateway,this.requestProof});
 final PersonalDetailsGateway? gateway;
 final PersonalProof? requestProof;
 @override State<PersonalDetailsPage> createState()=>_PersonalDetailsPageState();
}
class _PersonalDetailsPageState extends State<PersonalDetailsPage> {
 PersonalDetailsGateway? _gateway;
 final _birth=TextEditingController(),_bank=TextEditingController(),_branch=TextEditingController(),_number=TextEditingController(),_holder=TextEditingController();
 String _type='普通';bool _busy=true,_birthDirty=false,_bankDirty=false,_clearBank=false;
 PersonalDetailsSummary? _summary;String? _error;
 @override void initState(){super.initState();_gateway=widget.gateway??PersonalDetailsRepository.maybeCreate();_gateway?.addListener(_scopeChanged);_load();}
 void _clear(){for(final c in [_birth,_bank,_branch,_number,_holder]){c.clear();}_birthDirty=false;_bankDirty=false;_clearBank=false;}
 void _scopeChanged(){if(_gateway?.isCurrent!=true&&mounted){_clear();setState((){_summary=null;_error='ログイン状態が変わりました。画面を開き直してください。';_busy=false;});}}
 @override void dispose(){_gateway?.removeListener(_scopeChanged);if(widget.gateway==null)_gateway?.close();for(final c in [_birth,_bank,_branch,_number,_holder]){c.clear();c.dispose();}super.dispose();}
 Future<void> _load() async {
  final gateway=_gateway;if(gateway==null){if(mounted)setState((){_busy=false;_error='個人情報を利用できません。';});return;}
  _clear();setState((){_busy=true;_error=null;_summary=null;});
  try {final value=await gateway.load();if(!mounted||!gateway.isCurrent)return;
   _clear();_birth.text=value.birthDate??'';setState(()=>_summary=value);
  }catch(_){if(mounted)setState(()=>_error='個人情報を確認できません。未登録とは判断せず、再読み込みしてください。');}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<String?> _proof(String operation,Map<String,dynamic> target) async {
  final gateway=_gateway!;if(!gateway.isCurrent)return null;
  if(widget.requestProof!=null)return widget.requestProof!(operation,target);
  final verifier=OperationReauthenticationRepository.maybeCreate();if(verifier==null)throw StateError('本人確認を利用できません。');
  return showDialog<String>(context:context,barrierDismissible:false,builder:(_)=>MasterFeatureProofDialog(
   expectedActor:gateway.actorId,currentActor:()=>gateway.isCurrent?gateway.actorId:null,
   label:'個人情報',enabled:true,title:'個人情報の本人確認',
   description:'ログイン用の本パスワードで本人確認してください。会社の書類情報は変更しません。',confirmLabel:'本人確認',
   requestProof:(password)=>verifier.requestProof(password:password,operation:operation,target:target)));
 }
 Future<void> _readBank() async {
  final gateway=_gateway!,summary=_summary!;setState(()=>_busy=true);
  try {final bank=await gateway.readBank(summary.revision,_proof);if(!mounted||!gateway.isCurrent)return;
   if(bank!=null){_bank.text=bank.bankName;_branch.text=bank.branchName;_number.text=bank.accountNumber;_holder.text=bank.accountHolder;setState(()=>_type=bank.accountType);}
  }catch(_){if(mounted)setState(()=>_error='口座内容を確認できません。再度読み込んでください。');}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 String _operation(){final random=Random.secure();final b=List.generate(16,(_)=>random.nextInt(256));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;final h=b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join();return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';}
 Future<void> _save() async {
  final gateway=_gateway!,summary=_summary!;if(!gateway.isCurrent||gateway.pendingUnknown)return;
  final changes=<String,dynamic>{};
  if(_birthDirty){final raw=_birth.text.trim();if(!personalBirthDateValid(raw.isEmpty?null:raw)){setState(()=>_error='本人の誕生日をYYYY-MM-DD形式で確認してください。');return;}changes['birth_date']=raw.isEmpty?null:raw;}
  if(_bankDirty){if(_clearBank){changes['bank_account']=null;}else{
   final bank=OwnBankAccountInput(bankName:_bank.text,branchName:_branch.text,accountType:_type,accountNumber:_number.text,accountHolder:_holder.text);
   if(!bank.isValid){setState(()=>_error='銀行名・支店名・口座種別・7桁の口座番号・口座名義を確認してください。');return;}changes['bank_account']=personalBankJson(bank);
  }}
  if(changes.isEmpty)return;
  final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
   title:const Text('個人情報を保存しますか？'),content:Text('変更する項目：${changes.containsKey('birth_date')?'本人の誕生日 ':''}${changes.containsKey('bank_account')?'個人口座 ':''}\nこの本人アカウントの個人情報として保存します。会社書類・発行済み給与明細は変更しません。'),
   actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('戻る')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('確認して保存'))]));
  if(confirmed!=true||!mounted||!gateway.isCurrent)return;
  setState((){_busy=true;_error=null;});
  try {final saved=await gateway.save(summary.revision,changes,_operation(),_proof);if(!mounted||!gateway.isCurrent)return;
   if(saved){_clear();ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('個人情報を保存しました。')));await _load();}
  }catch(_){if(mounted){_clear();setState(()=>_error=gateway.pendingUnknown?const PersonalDetailsUnconfirmed().toString():'保存できませんでした。変更結果を確認してから操作してください。');}}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _reconcile() async {
  final gateway=_gateway!;setState(()=>_busy=true);
  try{final applied=await gateway.reconcile();if(!mounted||!gateway.isCurrent)return;
   if(applied){await _load();}else{setState(()=>_error='保存結果は不明です。再送せず、そのまま保持しています。');}
  }catch(_){if(mounted)setState(()=>_error='保存結果を確認できません。再送せず保持しています。');}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context){final gateway=_gateway,summary=_summary;final editable=!_busy&&summary!=null&&gateway?.isCurrent==true&&gateway?.pendingUnknown==false;
  return Scaffold(appBar:AppBar(title:const Text('個人プロフィール')),body:ListView(padding:const EdgeInsets.all(16),children:[
   const Text('本人の誕生日・個人口座。会社への提出書類や家族の誕生日とは別に保存します。'),
   if(_busy)const LinearProgressIndicator(),if(_error!=null)Text(_error!,key:const Key('personal-details-error')),
   if(gateway?.pendingUnknown==true)...[const Text('前回の保存結果を確認するまで、新しい保存は行いません。'),OutlinedButton(onPressed:_busy?null:_reconcile,child:const Text('保存結果を確認'))],
   OutlinedButton(onPressed:_busy?null:_load,child:const Text('再読み込み')),
   if(summary!=null)...[
    TextField(key:const Key('personal-birth-date'),controller:_birth,enabled:editable,decoration:const InputDecoration(labelText:'本人の誕生日（YYYY-MM-DD）',helperText:'介護保険の年齢判定に使用します。'),onChanged:(_)=>setState(()=>_birthDirty=true)),
    Text(summary.bankRegistered?'この個人プロフィールに口座の記録があります。':'この個人プロフィールに口座は登録されていません。'),
    if(summary.bankRegistered)OutlinedButton(onPressed:editable?_readBank:null,child:const Text('本人確認して口座を表示')),
    for(final f in [(_bank,'銀行名','personal-bank-name'),(_branch,'支店名','personal-bank-branch'),(_number,'口座番号（7桁）','personal-bank-number'),(_holder,'口座名義','personal-bank-holder')])TextField(key:Key(f.$3),controller:f.$1,enabled:editable&&!_clearBank,decoration:InputDecoration(labelText:f.$2),onChanged:(_)=>setState(()=>_bankDirty=true)),
    DropdownButtonFormField<String>(key:ValueKey(_type),initialValue:_type,decoration:const InputDecoration(labelText:'口座種別'),items:[for(final t in ['普通','当座','貯蓄'])DropdownMenuItem(value:t,child:Text(t))],onChanged:editable&&!_clearBank?(v)=>setState((){_type=v!;_bankDirty=true;}):null),
    CheckboxListTile(value:_clearBank,onChanged:editable?(v)=>setState((){_clearBank=v!;_bankDirty=true;}):null,title:const Text('個人口座の登録を削除する（確認後に反映）')),
    FilledButton(onPressed:editable&&(_bankDirty||_birthDirty)?_save:null,child:const Text('変更内容を確認して保存')),
   ],
  ]));
 }
}
