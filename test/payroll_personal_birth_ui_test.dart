import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payroll_tax_conditions_page.dart';
void main(){
 Map<String,dynamic> conditions()=>{'insurance_mode':'rates','income_mode':'fixed','health':true,'pension':false,'employment':false,'child_support':false,'nursing':true,'birth_date':'1986-10-01','health_base_yen':300000,'pension_base_yen':0,'dependents':0,'non_taxable_yen':0,'employment_excluded_yen':0,'additional_social_deduction_yen':0};
 testWidgets('adopted nursing saves NULL company DOB after confirmation with no duplicate DOB editor',(t)async{
  t.view.physicalSize=const Size(1000,2600);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  Map<String,dynamic>? sent;
  await t.pumpWidget(MaterialApp(home:PayrollTaxConditionsPage(companyId:'company',workerId:'worker',month:DateTime(2026,9),rpc:(name,args)async{
   if(name=='save_worker_payroll_tax_conditions')sent=Map.from(args['p_value'] as Map);
   return {'company_id':'company','worker_id':'worker','can_edit':true,'birth_source':'personal_uid_v1','items':[{'starts_on':'2026-09-01','version':sent==null?1:2,'value':sent??conditions()}]};
  })));await t.pumpAndSettle();
  expect(find.widgetWithText(TextFormField,'生年月日（YYYY-MM-DD）'),findsNothing);expect(find.text('1986-10-01'),findsNothing);
  await t.scrollUntilVisible(find.widgetWithText(FilledButton,'確認して保存'),500,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton,'確認して保存'));await t.pumpAndSettle();expect(sent,null);
  await t.tap(find.widgetWithText(FilledButton,'確認して保存').last);await t.pumpAndSettle();
  expect(sent,isNotNull);expect(sent!['birth_date'],null);expect(sent!['nursing'],true);
 });
 testWidgets('legacy source absence rejects rates nursing save and never offers company DOB fallback',(t)async{
  var writes=0;await t.pumpWidget(MaterialApp(home:PayrollTaxConditionsPage(companyId:'company',workerId:'worker',rpc:(name,args)async{
   if(name.startsWith('save_'))writes++;
   return {'company_id':'company','worker_id':'worker','can_edit':true,'items':[{'starts_on':'2026-09-01','version':1,'value':conditions()}]};
  })));await t.pumpAndSettle();
  await t.scrollUntilVisible(find.byKey(const ValueKey('payroll-personal-birth-unavailable')),500,scrollable:find.byType(Scrollable).first);await t.pumpAndSettle();
  expect(find.byKey(const ValueKey('payroll-personal-birth-unavailable')),findsOneWidget);
  await t.scrollUntilVisible(find.widgetWithText(FilledButton,'確認して保存'),500,scrollable:find.byType(Scrollable).first);
  await t.tap(find.widgetWithText(FilledButton,'確認して保存'));await t.pumpAndSettle();expect(writes,0);
  expect(find.widgetWithText(TextFormField,'生年月日（YYYY-MM-DD）'),findsNothing);
 });
 testWidgets('legacy source absence allows unrelated fixed conditions save',(t)async{
  t.view.physicalSize=const Size(1000,2600);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  Map<String,dynamic>? sent;
  await t.pumpWidget(MaterialApp(home:PayrollTaxConditionsPage(companyId:'company',workerId:'worker',rpc:(name,args)async{
   if(name.startsWith('save_'))sent=Map.from(args['p_value'] as Map);
   return {'company_id':'company','worker_id':'worker','can_edit':true,'items':[{'starts_on':'2026-09-01','version':sent==null?1:2,'value':sent??({...conditions(),'insurance_mode':'fixed'})}]};
  })));await t.pumpAndSettle();
  await t.scrollUntilVisible(find.widgetWithText(FilledButton,'確認して保存'),500,scrollable:find.byType(Scrollable).first);await t.tap(find.widgetWithText(FilledButton,'確認して保存'));await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton,'確認して保存').last);await t.pumpAndSettle();expect(sent,isNotNull);expect(sent!['birth_date'],'1986-10-01');
 });
 testWidgets('unlinked company DOB remains editable and saves company date without profile import',(t)async{
  t.view.physicalSize=const Size(1000,2600);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  Map<String,dynamic>? sent;
  await t.pumpWidget(MaterialApp(home:PayrollTaxConditionsPage(companyId:'company',workerId:'worker',rpc:(name,args)async{
   if(name.startsWith('save_'))sent=Map.from(args['p_value'] as Map);
   return {'company_id':'company','worker_id':'worker','can_edit':true,'birth_source':'company_worker_unlinked_v1','items':[{'starts_on':'2026-09-01','version':sent==null?1:2,'value':sent??conditions()}]};
  })));await t.pumpAndSettle();
  final birth=find.widgetWithText(TextFormField,'生年月日（YYYY-MM-DD）');expect(birth,findsOneWidget);
  expect(t.widget<TextFormField>(birth).controller!.text,'1986-10-01');
  await t.scrollUntilVisible(birth,400,scrollable:find.byType(Scrollable).first);await t.enterText(birth,'1985-03-02');t.testTextInput.hide();await t.pumpAndSettle();
  await t.scrollUntilVisible(find.widgetWithText(FilledButton,'確認して保存'),500,scrollable:find.byType(Scrollable).first);await t.tap(find.widgetWithText(FilledButton,'確認して保存'));await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton,'確認して保存').last);await t.pumpAndSettle();expect(sent!['birth_date'],'1985-03-02');expect(sent!['nursing'],true);
 });
 testWidgets('unlinked requested nursing requires company DOB and never guesses absent date',(t)async{
  t.view.physicalSize=const Size(1000,2600);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  var writes=0;
  await t.pumpWidget(MaterialApp(home:PayrollTaxConditionsPage(companyId:'company',workerId:'worker',rpc:(name,args)async{
   if(name.startsWith('save_'))writes++;
   return {'company_id':'company','worker_id':'worker','can_edit':true,'birth_source':'company_worker_unlinked_v1','items':[{'starts_on':'2026-09-01','version':1,'value':{...conditions(),'birth_date':null}}]};
  })));await t.pumpAndSettle();
  final birth=find.widgetWithText(TextFormField,'生年月日（YYYY-MM-DD）');
  expect(t.widget<TextFormField>(birth).validator!(null),'生年月日を入力してください');
  await t.scrollUntilVisible(find.widgetWithText(FilledButton,'確認して保存'),500,scrollable:find.byType(Scrollable).first);await t.tap(find.widgetWithText(FilledButton,'確認して保存'));await t.pumpAndSettle();expect(writes,0);expect(find.byType(AlertDialog),findsNothing);
  expect(find.byKey(const ValueKey('insurance-base-input-error')),findsOneWidget);
 });
 testWidgets('missing marker unrelated fixed save preserves loaded company DOB without exposing editor',(t)async{
  t.view.physicalSize=const Size(1000,2600);t.view.devicePixelRatio=1;addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  Map<String,dynamic>? sent;
  final existing={...conditions(),'insurance_mode':'fixed','birth_date':'1978-04-05'};
  await t.pumpWidget(MaterialApp(home:PayrollTaxConditionsPage(companyId:'company',workerId:'worker',rpc:(name,args)async{
   if(name.startsWith('save_'))sent=Map.from(args['p_value'] as Map);
   return {'company_id':'company','worker_id':'worker','can_edit':true,'items':[{'starts_on':'2026-09-01','version':sent==null?1:2,'value':sent??existing}]};
  })));await t.pumpAndSettle();
  expect(find.widgetWithText(TextFormField,'生年月日（YYYY-MM-DD）'),findsNothing);
  await t.scrollUntilVisible(find.widgetWithText(FilledButton,'確認して保存'),500,scrollable:find.byType(Scrollable).first);await t.tap(find.widgetWithText(FilledButton,'確認して保存'));await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton,'確認して保存').last);await t.pumpAndSettle();
  expect(sent,isNotNull);expect(sent!['birth_date'],'1978-04-05');expect(sent!['insurance_mode'],'fixed');
 });
}
