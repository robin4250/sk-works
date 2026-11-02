import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/language_controller.dart';
import 'package:sk_works/international/language_pack_registry.dart';
import 'package:sk_works/features/profile/personal_details_page.dart';
import 'package:sk_works/features/profile/personal_details_repository.dart';
import 'package:sk_works/features/people/own_bank_account_repository.dart';
import 'package:sk_works/features/settings/master_feature_proof_dialog.dart';
class _Gateway extends ChangeNotifier implements PersonalDetailsGateway {
 @override String get actorId=>'10000000-0000-4000-8000-000000000001';
 @override bool isCurrent=true;
 @override bool pendingUnknown=false;
 int loads=0,writes=0;Map<String,dynamic>? changes;bool unknown=false;
 @override Future<PersonalDetailsSummary> load()async{loads++;return const PersonalDetailsSummary(revision:0,exists:false,bankRegistered:false);}
 @override Future<OwnBankAccountInput?> readBank(int r,PersonalProof p)async=>null;
 @override Future<bool> save(int r,Map<String,dynamic> c,String o,PersonalProof p)async{writes++;changes=c;if(unknown){pendingUnknown=true;throw const PersonalDetailsUnconfirmed();}return true;}
 @override Future<bool> reconcile()async=>false;
 @override Future<void> close()async{}
}
class _Host extends StatelessWidget {
 const _Host(this.home);final Widget home;
 @override Widget build(BuildContext context)=>ValueListenableBuilder(valueListenable:SkoLanguageController.pack,builder:(context,pack,_)=>MaterialApp(locale:Locale(pack.languageCode),supportedLocales:const [Locale('ja'),Locale('en')],localizationsDelegates:GlobalMaterialLocalizations.delegates,home:home));
}
void language(String code)=>SkoLanguageController.pack.value=LanguagePackRegistry.resolve(code);
void main(){
 setUp(()=>language('ja'));tearDown(()=>language('ja'));
 void large(WidgetTester t){t.view.physicalSize=const Size(1100,2400);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);}
 testWidgets('JA EN JA preserves opened route, edited values and live confirmation dialog',(t)async{
  large(t);final g=_Gateway();await t.pumpWidget(_Host(PersonalDetailsPage(gateway:g)));await t.pumpAndSettle();
  final state=t.state(find.byType(PersonalDetailsPage));await t.enterText(find.byKey(const Key('personal-birth-date')),'1990-01-02');await t.enterText(find.byKey(const Key('personal-bank-name')),'SYNTHETIC BANK');
  language('en');await t.pumpAndSettle();expect(find.text('Personal profile'),findsOneWidget);expect(t.widget<TextField>(find.byKey(const Key('personal-birth-date'))).controller!.text,'1990-01-02');expect(t.widget<TextField>(find.byKey(const Key('personal-bank-name'))).controller!.text,'SYNTHETIC BANK');expect(identical(state,t.state(find.byType(PersonalDetailsPage))),true);expect(g.loads,1);
  // Cancel bank dirty input here so the date-only confirmation is valid.
  await t.tap(find.text('Reload'));await t.pumpAndSettle();await t.enterText(find.byKey(const Key('personal-birth-date')),'1990-01-02');await t.pump();
  await t.tap(find.text('Review changes and save'));await t.pumpAndSettle();expect(find.text('Save your personal information?'),findsOneWidget);expect(g.writes,0);
  language('ja');await t.pumpAndSettle();expect(find.text('個人情報を保存しますか？'),findsOneWidget);expect(find.textContaining('変更する項目：本人の誕生日'),findsOneWidget);await t.tap(find.text('戻る'));await t.pumpAndSettle();expect(t.widget<TextField>(find.byKey(const Key('personal-birth-date'))).controller!.text,'1990-01-02');expect(g.writes,0);
 });
 testWidgets('English account labels keep Japanese account-type protocol values',(t)async{
  large(t);language('en');final g=_Gateway();await t.pumpWidget(_Host(PersonalDetailsPage(gateway:g)));await t.pumpAndSettle();
  for(final e in {'personal-bank-name':'普通','personal-bank-branch':'SYNTHETIC BRANCH','personal-bank-number':'0000001','personal-bank-holder':'SYNTHETIC HOLDER'}.entries){await t.enterText(find.byKey(Key(e.key)),e.value);}
  await t.tap(find.byType(DropdownButtonFormField<String>));await t.pumpAndSettle();await t.tap(find.text('Current').last);await t.pumpAndSettle();
  expect(t.widget<TextField>(find.byKey(const Key('personal-bank-name'))).controller!.text,'普通');
  await t.tap(find.text('Review changes and save'));await t.pumpAndSettle();await t.tap(find.text('Confirm and save'));await t.pumpAndSettle();expect(g.writes,1);expect((g.changes!['bank_account'] as Map)['account_type'],'当座');expect((g.changes!['bank_account'] as Map)['bank_name'],'普通');
 });
 testWidgets('unknown-save error translates in place and never retries',(t)async{
  large(t);language('en');final g=_Gateway()..unknown=true;await t.pumpWidget(_Host(PersonalDetailsPage(gateway:g)));await t.pumpAndSettle();await t.enterText(find.byKey(const Key('personal-birth-date')),'1990-01-02');await t.pump();await t.tap(find.text('Review changes and save'));await t.pumpAndSettle();await t.tap(find.text('Confirm and save'));await t.pumpAndSettle();
  expect(find.text('The save result is uncertain. Do not resend; select Check save result.'),findsOneWidget);expect(find.text('Check save result'),findsOneWidget);expect(g.writes,1);
  language('ja');await t.pumpAndSettle();expect(find.text(const PersonalDetailsUnconfirmed().toString()),findsOneWidget);expect(g.writes,1);
 });
 testWidgets('open proof dialog follows locale without changing credential controller',(t)async{
  large(t);await t.pumpWidget(_Host(Scaffold(body:Builder(builder:(context)=>TextButton(onPressed:()=>showDialog<void>(context:context,builder:(_)=>MasterFeatureProofDialog(expectedActor:'synthetic',currentActor:()=>'synthetic',requestProof:(_)async=>'synthetic-proof',label:'個人情報',enabled:true,title:'個人情報の本人確認',description:'ログイン用の本パスワードで本人確認してください。会社の書類情報は変更しません。',confirmLabel:'本人確認')),child:const Text('open'))))));await t.tap(find.text('open'));await t.pumpAndSettle();await t.enterText(find.byKey(const Key('master-feature-password')),'synthetic');
  language('en');await t.pumpAndSettle();expect(find.text('Verify your identity for personal information'),findsOneWidget);expect(find.text('Sign-in password'),findsOneWidget);expect(t.widget<TextField>(find.byKey(const Key('master-feature-password'))).controller!.text,'synthetic');
  language('ja');await t.pumpAndSettle();expect(find.text('個人情報の本人確認'),findsOneWidget);await t.tap(find.text('キャンセル'));await t.pumpAndSettle();
 });
}
