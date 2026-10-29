import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'employee_bank_account_repository.dart';
import 'own_bank_account_page.dart';
import 'own_bank_account_repository.dart';

class EmployeeBankAccountSection extends StatefulWidget {
  const EmployeeBankAccountSection({super.key,required this.workerId,required this.companyId,required this.employeeName,this.gateway});
  final String workerId,companyId,employeeName;
  final EmployeeBankAccountGateway? gateway;
  @override State<EmployeeBankAccountSection> createState()=>_SectionState();
}
class _SectionState extends State<EmployeeBankAccountSection> {
  EmployeeBankAccountGateway? _gateway;
  EmployeeBankAccountState? _state;
  bool _busy=true;
  String? _error;
  int _generation=0;
  @override void initState(){super.initState();_start();}
  void _start(){
    try {_gateway=widget.gateway??EmployeeBankAccountRepository.maybeCreate(companyId:widget.companyId,workerId:widget.workerId);_gateway?.addListener(_changed);}catch(_){/* No stale scope fallback. */}
    _load();
  }
  void _changed(){if(mounted&&_gateway?.isCurrent!=true){_generation++;setState((){_state=null;_busy=false;_error='ログイン状態が変わりました。社員情報を開き直してください。';});}}
  @override void didUpdateWidget(EmployeeBankAccountSection old){
    super.didUpdateWidget(old);
    if(old.companyId!=widget.companyId||old.workerId!=widget.workerId||old.gateway!=widget.gateway){
      _generation++;final previous=_gateway;previous?.removeListener(_changed);
      if(old.gateway==null&&previous!=null)unawaited(previous.close());
      _gateway=null;_state=null;_busy=true;_error=null;_start();
    }
  }
  bool _matches(EmployeeBankAccountState value)=>value.companyId==widget.companyId.toLowerCase()&&value.workerId==widget.workerId.toLowerCase();
  Future<void> _load() async {
    final gateway=_gateway;final generation=++_generation;
    if(gateway==null){if(mounted)setState((){_busy=false;_error='銀行口座の登録状態を確認できません。';});return;}
    if(mounted)setState((){_busy=true;_error=null;});
    try{final value=await gateway.load();if(!mounted||generation!=_generation||!gateway.isCurrent)return;
      if(!_matches(value))throw StateError('Selected employee changed');setState((){_state=value;_busy=false;});
    }catch(_){if(mounted&&generation==_generation)setState((){_state=null;_busy=false;_error='銀行口座の登録状態を確認できません。権限と対象社員を確認してください。';});}
  }
  Future<void> _open() async {
    final gateway=_gateway,state=_state;
    if(_busy||gateway==null||!gateway.isCurrent||state==null||!state.canRegister||!_matches(state))return;
    final generation=++_generation;setState(()=>_busy=true);
    try{
      final current=await gateway.load();
      if(!mounted||generation!=_generation||!gateway.isCurrent||!_matches(current))return;
      setState(()=>_state=current);if(!current.canRegister)return;
      final self=gateway.selfGateway;
      if(current.self&&self==null)throw StateError('Selected own scope unavailable');
      await Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>current.self
        ? OwnBankAccountPage(workerId:widget.workerId,companyId:widget.companyId,gateway:self)
        : _EmployeeBankInitialPage(gateway:gateway,companyId:widget.companyId,workerId:widget.workerId,employeeName:widget.employeeName)));
      if(mounted&&generation==_generation)await _load();
    }catch(_){if(mounted&&generation==_generation)setState(()=>_error='登録画面を開けません。社員情報を再確認してください。');}
    finally{if(mounted&&generation==_generation)setState(()=>_busy=false);}
  }
  @override void dispose(){_generation++;final gateway=_gateway;gateway?.removeListener(_changed);if(widget.gateway==null&&gateway!=null)unawaited(gateway.close());super.dispose();}
  @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('銀行口座情報',style:TextStyle(fontWeight:FontWeight.bold)),
    Text('対象社員：${widget.employeeName}'),
    if(_busy)const LinearProgressIndicator(),
    if(_error!=null)Text(_error!),
    if(_state?.registered==true)const Text('登録済みの銀行口座情報は保持しています。'),
    if(_state?.registered==false)const Text('銀行口座情報は未登録です。'),
    if(_state!=null&&!_state!.self&&(!_state!.available||!_state!.managerEnabled))const Text('管理者による初回登録は導入準備中です。'),
    if(_state?.canRegister==true)FilledButton(onPressed:_busy?null:_open,child:Text(_state!.self?'本人の銀行口座を登録':'この社員の銀行口座を登録')),
    TextButton(onPressed:_busy||_gateway?.isCurrent==false?null:_load,child:const Text('登録状態を再確認')),
  ])));
}
class _EmployeeBankInitialPage extends StatefulWidget {
  const _EmployeeBankInitialPage({required this.gateway,required this.companyId,required this.workerId,required this.employeeName});
  final EmployeeBankAccountGateway gateway;
  final String companyId,workerId,employeeName;
  @override State<_EmployeeBankInitialPage> createState()=>_InitialState();
}
class _InitialState extends State<_EmployeeBankInitialPage> {
  final _form=GlobalKey<FormState>();
  final _bank=TextEditingController(),_branch=TextEditingController(),_number=TextEditingController(),_holder=TextEditingController();
  String _type='普通';String? _error;bool _busy=false,_registered=false,_unconfirmed=false;int _generation=0;
  @override void initState(){super.initState();widget.gateway.addListener(_changed);}
  void _clear(){for(final c in [_bank,_branch,_number,_holder]){c.clear();}}
  void _changed(){if(mounted&&!widget.gateway.isCurrent){_generation++;_clear();setState((){_busy=false;_unconfirmed=true;_error='ログイン状態が変わりました。社員情報を開き直してください。';});}}
  Future<void> _save() async {
    if(_busy||_registered||_unconfirmed||!widget.gateway.isCurrent||_form.currentState?.validate()!=true)return;
    final input=OwnBankAccountInput(bankName:_bank.text,branchName:_branch.text,accountType:_type,accountNumber:_number.text,accountHolder:_holder.text);
    if(!input.isValid)return;
    final generation=++_generation;setState((){_busy=true;_error=null;});
    try{
      final saved=await widget.gateway.register(input,requestPassword:()=>showDialog<String>(context:context,barrierDismissible:false,
        builder:(_)=>_BankPasswordDialog(gateway:widget.gateway,employeeName:widget.employeeName)));
      if(!mounted||generation!=_generation||!widget.gateway.isCurrent)return;
      if(saved.companyId!=widget.companyId.toLowerCase()||saved.workerId!=widget.workerId.toLowerCase()||saved.registered!=true||saved.self)throw StateError('Unconfirmed selected employee');
      _clear();setState((){_registered=true;_busy=false;});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('対象社員の銀行口座情報を登録しました')));
    }catch(_){if(mounted&&generation==_generation)setState((){_busy=false;_unconfirmed=true;_error='保存結果を確認できません。社員情報に戻り登録状態を再確認してください。';});}
  }
  @override void dispose(){_generation++;widget.gateway.removeListener(_changed);for(final c in [_bank,_branch,_number,_holder]){c.clear();c.dispose();}super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('社員の銀行口座を初回登録')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
    Text('対象社員：${widget.employeeName}',style:const TextStyle(fontWeight:FontWeight.bold)),
    const Text('対象社員の給与振込先を初回登録します。内容を確認して、本パスワードで本人確認してください。'),
    if(_busy)const LinearProgressIndicator(),if(_error!=null)Text(_error!),
    if(_registered)const Text('対象社員の銀行口座情報は登録済みです。'),
    if(!_registered&&!_unconfirmed)Form(key:_form,child:Column(children:[
      for(final entry in [(_bank,'銀行名','employee-bank-name'),(_branch,'支店名','employee-bank-branch'),(_holder,'口座名義（カナ）','employee-bank-holder')])
        TextFormField(key:Key(entry.$3),controller:entry.$1,enabled:!_busy,maxLength:100,decoration:InputDecoration(labelText:entry.$2),validator:(v)=>v?.trim().isNotEmpty==true?null:'${entry.$2}を入力してください。'),
      DropdownButtonFormField<String>(initialValue:_type,decoration:const InputDecoration(labelText:'預金種別'),items:[for(final type in ['普通','当座','貯蓄'])DropdownMenuItem(value:type,child:Text(type))],onChanged:_busy?null:(v)=>setState(()=>_type=v??'普通')),
      TextFormField(key:const Key('employee-bank-number'),controller:_number,enabled:!_busy,maxLength:7,keyboardType:TextInputType.number,inputFormatters:[FilteringTextInputFormatter.allow(RegExp(r'[0-9０-９]'))],decoration:const InputDecoration(labelText:'口座番号（7桁）'),validator:(v)=>RegExp(r'^[0-9０-９]{7}$').hasMatch(v??'')?null:'口座番号は7桁で入力してください。'),
      FilledButton(onPressed:_busy?null:_save,child:const Text('本パスワードで確認して登録')),
    ])),
  ])));
}
class _BankPasswordDialog extends StatefulWidget {
  const _BankPasswordDialog({required this.gateway,required this.employeeName});
  final EmployeeBankAccountGateway gateway;final String employeeName;
  @override State<_BankPasswordDialog> createState()=>_PasswordState();
}
class _PasswordState extends State<_BankPasswordDialog> {
  final _password=TextEditingController();bool _invalid=false;
  @override void initState(){super.initState();widget.gateway.addListener(_changed);}
  void _changed(){if(mounted&&!widget.gateway.isCurrent){_password.clear();setState(()=>_invalid=true);}}
  void _return(){if(_invalid||!widget.gateway.isCurrent||_password.text.isEmpty){_password.clear();return;}final value=_password.text;_password.clear();Navigator.pop(context,value);}
  @override void dispose(){widget.gateway.removeListener(_changed);_password.clear();_password.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('初回口座登録の本人確認'),content:Column(mainAxisSize:MainAxisSize.min,children:[
    Text('「${widget.employeeName}」の口座を初回登録します。管理者本人のログイン用本パスワードで確認してください。'),
    TextField(key:const Key('employee-bank-primary-password'),controller:_password,enabled:!_invalid,obscureText:true,autocorrect:false,enableSuggestions:false,onSubmitted:(_)=>_return(),decoration:const InputDecoration(labelText:'ログイン用の本パスワード')),
    if(_invalid)const Text('ログイン状態が変わりました。'),
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('キャンセル')),FilledButton(onPressed:_invalid?null:_return,child:const Text('本人確認して登録'))]);
}
