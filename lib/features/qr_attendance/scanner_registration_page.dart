import 'dart:async';
import 'package:flutter/material.dart';
import 'scanner_registration_controller.dart';

/// No app route imports this page. The controller and both native flags remain
/// OFF by default. This widget owns and disposes its controller.
class ScannerRegistrationPage extends StatefulWidget {
 const ScannerRegistrationPage({super.key,required this.controller,required this.companyName});
 final ScannerRegistrationController controller;
 final String companyName;
 @override State<ScannerRegistrationPage> createState()=>_ScannerRegistrationPageState();
}
class _ScannerRegistrationPageState extends State<ScannerRegistrationPage> {
 final _password=TextEditingController();
 bool _newDeviceConfirmed=false;
 @override void initState(){super.initState();widget.controller.addListener(_changed);WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)unawaited(widget.controller.load());});}
 void _changed(){if(!mounted)return;if(widget.controller.view!=ScannerRegistrationView.password && widget.controller.view!=ScannerRegistrationView.wrongPassword)_password.clear();setState((){});}
 @override void didUpdateWidget(covariant ScannerRegistrationPage oldWidget){super.didUpdateWidget(oldWidget);if(!identical(oldWidget.controller,widget.controller)){oldWidget.controller.removeListener(_changed);oldWidget.controller.dispose();_password.clear();_newDeviceConfirmed=false;widget.controller.addListener(_changed);unawaited(widget.controller.load());}}
 @override void dispose(){widget.controller.removeListener(_changed);widget.controller.dispose();_password.clear();_password.dispose();super.dispose();}
 String get _message=>switch(widget.controller.view){
  ScannerRegistrationView.disabled=>'スキャナー登録は準備中です。',
  ScannerRegistrationView.loading||ScannerRegistrationView.busy=>'元の手続きを確認しています。',
  ScannerRegistrationView.newLogicalDevice=>'保存された登録手続きはありません。新しいスキャナーを登録する場合だけ開始してください。過去の結果が不明な場合は、元の手続きを確認してください。',
  ScannerRegistrationView.keyPreparation=>'新しいスキャナーの手続きを保存しました。この端末の本人確認を行って鍵を準備します。',
  ScannerRegistrationView.ready=>'この端末の鍵を準備しました。登録手続きを開始できます。',
  ScannerRegistrationView.password=>'専用パスワードを確認して、この端末のスキャナーを登録します。続いて端末の本人確認が必要です。',
  ScannerRegistrationView.wrongPassword=>'専用パスワードを確認できませんでした。入力内容を確認してください。',
  ScannerRegistrationView.uncertain=>'操作結果を確認できません。再送せず、元の手続きの結果を照合してください。',
  ScannerRegistrationView.proofLost=>'本人確認の受付記録はありますが、安全に続けるための確認情報がありません。登録完了とは確認できていません。手続きを繰り返さず、管理者に確認してください。',
  ScannerRegistrationView.confirmed=>'元の登録履歴を確認しました。QR打刻の有効化と実機確認は別途必要です。',
  ScannerRegistrationView.blocked=>'本人・会社・端末または保存状態を確認できないため、手続きを停止しました。新規登録を繰り返さず、元の手続きを確認してください。',
 };
 @override Widget build(BuildContext context){
  final c=widget.controller,showPassword=[ScannerRegistrationView.password,ScannerRegistrationView.wrongPassword].contains(widget.controller.view);
  final attempts=(c.pending?.data['proofRequestIds'] as List?)?.length??0;
  return Scaffold(appBar:AppBar(title:const Text('スキャナー登録')),body:SafeArea(child:SingleChildScrollView(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   Text(widget.companyName,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:16),Text(_message,key:const Key('scanner-registration-status')),const SizedBox(height:20),
   if(c.busy)const Center(child:CircularProgressIndicator()),
   if(c.view==ScannerRegistrationView.newLogicalDevice)...[
    CheckboxListTile(value:_newDeviceConfirmed,onChanged:c.busy?null:(value)=>setState(()=>_newDeviceConfirmed=value==true),title:const Text('新しい論理スキャナーの登録を開始する')),
    FilledButton(key:const Key('scanner-new-logical-device'),onPressed:_newDeviceConfirmed&&!c.busy?()=>unawaited(c.createExplicitNewLogicalDevice()):null,child:const Text('端末で本人確認して開始')),
   ],
   if(c.view==ScannerRegistrationView.keyPreparation)FilledButton(onPressed:c.busy?null:()=>unawaited(c.prepareKey()),child:const Text('この端末の鍵を準備')),
   if(c.view==ScannerRegistrationView.ready)FilledButton(onPressed:c.busy?null:()=>unawaited(c.startChallenge()),child:const Text('登録手続きを開始')),
   if(showPassword)...[
    TextField(key:const Key('scanner-dedicated-password'),controller:_password,obscureText:true,enableSuggestions:false,autocorrect:false,maxLength:1024,decoration:const InputDecoration(labelText:'専用パスワード')),
    FilledButton(onPressed:c.busy||attempts>=5?null:(){final password=_password.text;_password.clear();unawaited(c.submitPassword(password));},child:const Text('本人確認して登録')),
    if(attempts>=5)const Text('この手続きでは追加のパスワード確認を行えません。管理者に確認してください。'),
   ],
   if(c.canReconcile)OutlinedButton(key:const Key('scanner-reconcile'),onPressed:()=>unawaited(c.reconcile()),child:const Text('元の手続きを照合')),
   if(c.pending!=null)Padding(padding:const EdgeInsets.only(top:16),child:Text('管理番号: ${c.pending!.data['device']}',style:Theme.of(context).textTheme.bodySmall)),
  ]))));
 }
}
