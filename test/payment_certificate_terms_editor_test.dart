import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/payroll/payment_certificate_terms_draft.dart';
import 'package:sk_works/features/payroll/payment_certificate_terms_editor.dart';

Future<void> showEditor(WidgetTester t,{Future<void> Function(CertificateTermsDraft)? save}) async {
  await t.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(
    child:Padding(padding:const EdgeInsets.all(12),child:PaymentCertificateTermsEditor(
      initialValue:CertificateTermsDraft(),canEdit:true,onSave:save,
    )),
  ))));
  await t.pumpAndSettle();
}
Future<void> tap(WidgetTester t,String label)async{
  final target=find.text(label);
  await t.ensureVisible(target);await t.tap(target);await t.pumpAndSettle();
}
Finder field(String label)=>find.byWidgetPredicate((w)=>w is TextField && w.decoration?.labelText==label);
Future<void> item(WidgetTester t,String name,String amount)async{
  await tap(t,'項目を追加');
  await t.ensureVisible(field('項目名'));await t.enterText(field('項目名'),name);
  await t.ensureVisible(field('単価'));await t.enterText(field('単価'),amount);
}
void main(){
  test('hourly omits day division and monthly/contract use the separate daily input',(){
    expect(const CertificateBasisTerms(amountYen:2000).overtimeRate(CertificatePayBasis.hourly),2500);
    expect(const CertificateBasisTerms(amountYen:16000).overtimeRate(CertificatePayBasis.daily),2500);
    expect(const CertificateBasisTerms(amountYen:600000,calculationDailyYen:16000)
      .overtimeRate(CertificatePayBasis.monthly),2500);
    expect(const CertificateBasisTerms(amountYen:9999999,calculationDailyYen:16000)
      .overtimeRate(CertificatePayBasis.monthly),2500);
    expect(const CertificateBasisTerms(amountYen:900000,calculationDailyYen:24000)
      .overtimeRate(CertificatePayBasis.contract),3750);
  });
  testWidgets('four bases retain amounts, item groups and calculation daily rate across switches',(t)async{
    CertificateTermsDraft? saved;
    await showEditor(t,save:(value)async{saved=value;});
    await tap(t,'月給');
    await t.enterText(find.byKey(const ValueKey('base-monthly')),'600000');
    await t.enterText(find.byKey(const ValueKey('calculation-daily-monthly')),'16000');
    expect(t.getTopLeft(find.byKey(const ValueKey('calculation-daily-monthly'))).dy,
      lessThan(t.getTopLeft(find.text('計算式')).dy));
    expect(field('残業倍率'),findsNothing);
    await item(t,'手当A','2000');
    await tap(t,'差引き');await item(t,'差引A','300');
    await tap(t,'月単位');await item(t,'月額差引','500');
    await tap(t,'請負');
    await t.enterText(find.byKey(const ValueKey('base-contract')),'900000');
    await t.enterText(find.byKey(const ValueKey('calculation-daily-contract')),'24000');
    await tap(t,'月給');
    expect(t.widget<TextField>(find.byKey(const ValueKey('base-monthly'))).controller!.text,'600000');
    expect(t.widget<TextField>(find.byKey(const ValueKey('calculation-daily-monthly'))).controller!.text,'16000');
    await tap(t,'設定を保存');
    expect(saved!.bases[CertificatePayBasis.monthly]!.amountYen,600000);
    expect(saved!.bases[CertificatePayBasis.contract]!.amountYen,900000);
    expect(saved!.items.length,3);
    expect(saved!.items.where((i)=>i.direction==CertificateItemDirection.payment).length,1);
    expect(saved!.items.where((i)=>i.unit==CertificateItemUnit.month).single.name,'月額差引');
    expect(saved!.items.map((i)=>i.id).toSet().length,3);
    expect(t.takeException(),isNull);
  });
  testWidgets('missing storage keeps edits and save disabled',(t)async{
    await showEditor(t);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton,'設定を保存')).onPressed,isNull);
    expect(t.widget<TextField>(find.byKey(const ValueKey('base-daily'))).enabled,isFalse);
  });
  testWidgets('failed save retains all entered amounts',(t)async{
    await showEditor(t,save:(_)async{throw StateError('test failure');});
    await t.enterText(find.byKey(const ValueKey('base-daily')),'32800');
    await tap(t,'設定を保存');
    expect(find.textContaining('test failure'),findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('base-daily'))).controller!.text,'32800');
  });
  testWidgets('narrow width preserves requested order without overflow',(t)async{
    await t.binding.setSurfaceSize(const Size(320,900));
    addTearDown(()=>t.binding.setSurfaceSize(null));
    await showEditor(t,save:(_)async{});
    await tap(t,'月給');
    expect(t.takeException(),isNull);
    expect(t.getTopLeft(find.text('福利厚生費・消費税')).dy,
      greaterThan(t.getTopLeft(find.text('項目を追加')).dy));
  });
}
