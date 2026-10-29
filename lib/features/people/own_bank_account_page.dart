import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'own_bank_account_repository.dart';

class OwnBankAccountPage extends StatefulWidget {
  const OwnBankAccountPage({super.key, required this.workerId, required this.companyId, this.gateway});
  final String workerId, companyId;
  final OwnBankAccountGateway? gateway;
  @override
  State<OwnBankAccountPage> createState() => _OwnBankAccountPageState();
}

class _OwnBankAccountPageState extends State<OwnBankAccountPage> {
  OwnBankAccountGateway? _gateway;
  final _form = GlobalKey<FormState>();
  final _bank = TextEditingController(), _branch = TextEditingController(),
    _number = TextEditingController(), _holder = TextEditingController();
  String _type = '普通';
  OwnBankAccountState? _state;
  String? _error;
  bool _busy = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    try {
      _gateway = widget.gateway ?? OwnBankAccountRepository.maybeCreate(workerId:widget.workerId,companyId:widget.companyId);
      _gateway?.addListener(_changed);
    } catch (_) { /* No account data is exposed on unavailable authentication. */ }
    _load();
  }
  void _clear() { for (final c in [_bank,_branch,_number,_holder]) { c.clear(); } }
  void _changed() {
    if (!mounted || _gateway?.isCurrent == true) return;
    _generation++; _clear();
    setState(() { _state=null; _busy=false; _error='ログイン状態が変わりました。画面を開き直してください。'; });
  }
  Future<void> _load() async {
    final gateway=_gateway;
    if (gateway == null) {
      setState(() { _busy=false; _error='口座情報を利用できません。ログイン状態を確認してください。'; }); return;
    }
    final generation=++_generation;
    setState(() { _busy=true; _error=null; });
    try {
      final state=await gateway.load();
      if (!mounted || generation!=_generation || !gateway.isCurrent) return;
      if (state.registered) _clear();
      setState(() { _state=state; _busy=false; });
    } catch (_) {
      if (!mounted || generation!=_generation) return;
      setState(() { _state=null; _busy=false; _error='口座の登録状態を確認できません。再読み込みしてください。'; });
    }
  }
  Future<void> _save() async {
    final gateway=_gateway;
    if (_busy || gateway==null || !gateway.isCurrent || _state?.registered!=false || _form.currentState?.validate()!=true) return;
    final input=OwnBankAccountInput(bankName:_bank.text,branchName:_branch.text,accountType:_type,
      accountNumber:_number.text,accountHolder:_holder.text);
    if (!input.isValid) return;
    final generation=++_generation;
    setState(() { _busy=true; _error=null; });
    try {
      final state=await gateway.register(input);
      if (!mounted || generation!=_generation || !gateway.isCurrent) return;
      if (!state.registered) throw StateError('Unconfirmed bank registration');
      _clear();
      setState(() { _state=state; _busy=false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('銀行口座情報を登録しました')));
    } catch (_) {
      if (!mounted || generation!=_generation) return;
      // A request may have committed even when its response was lost. Read the
      // metadata again before another explicit attempt; never retry the write.
      setState(() { _state=null; _busy=false; _error='保存結果を確認できません。再読み込みして登録状態を確認してください。'; });
    }
  }
  @override
  void dispose() {
    _generation++; _gateway?.removeListener(_changed);
    if (widget.gateway==null && _gateway!=null) unawaited(_gateway!.close());
    for (final c in [_bank,_branch,_number,_holder]) { c.clear(); c.dispose(); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('銀行口座情報を登録')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('ログイン中の本人の給与振込先を登録します。会社の請求書用口座とは別の情報です。'),
      if (_busy) const LinearProgressIndicator(),
      if (_error!=null) ...[
        Text(_error!),
        OutlinedButton(onPressed:_busy || _gateway?.isCurrent!=true ? null : _load,child:const Text('再読み込み')),
      ],
      if (_state?.registered==true) ...[
        const Text('銀行口座情報は登録済みです。'),
        const Text('登録済みの口座情報は保持しています。この画面から変更・削除は行いません。'),
      ],
      if (_state?.registered==false) Form(key:_form,child:Column(children:[
        for (final entry in [(_bank,'銀行名','bank-name'),(_branch,'支店名','bank-branch')])
          TextFormField(key:Key(entry.$3),controller:entry.$1,enabled:!_busy,maxLength:100,
            decoration:InputDecoration(labelText:entry.$2),validator:(v)=>v?.trim().isNotEmpty==true ? null : '${entry.$2}を入力してください。'),
        DropdownButtonFormField<String>(initialValue:_type,decoration:const InputDecoration(labelText:'預金種別'),
          items:[for (final type in ['普通','当座','貯蓄']) DropdownMenuItem(value:type,child:Text(type))],
          onChanged:_busy ? null : (v)=>setState(()=>_type=v??'普通')),
        TextFormField(key:const Key('bank-number'),controller:_number,enabled:!_busy,
          keyboardType:TextInputType.number, maxLength:7,
          inputFormatters:[FilteringTextInputFormatter.allow(RegExp(r'[0-9０-９]'))],
          decoration:const InputDecoration(labelText:'口座番号（7桁）',helperText:'先頭の0も含めて7桁入力してください。'),
          validator:(v)=>RegExp(r'^[0-9０-９]{7}$').hasMatch(v??'') ? null : '口座番号は7桁で入力してください。'),
        TextFormField(key:const Key('bank-holder'),controller:_holder,enabled:!_busy,maxLength:100,
          decoration:const InputDecoration(labelText:'口座名義（カナ）'),
          validator:(v)=>v?.trim().isNotEmpty==true ? null : '口座名義を入力してください。'),
        const SizedBox(height:16),
        FilledButton(onPressed:_busy ? null : _save,child:const Text('銀行口座情報を登録')),
      ])),
    ])),
  );
}
