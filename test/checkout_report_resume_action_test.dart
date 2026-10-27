import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_report_resume_repository.dart';
import 'package:sk_works/features/attendance/checkout_report_resume_action.dart';

CheckoutReportResumeTarget _target({bool reporter = false, bool responsible = false, bool complete = false}) =>
    CheckoutReportResumeTarget(companyId: 'company', workerId: 'worker',
      workDate: DateTime(2026,10,21), sourceClockInIds: const ['saved-start'],
      clockOutIds: const ['saved-end'], sourceClockInId: 'saved-start', clockOutId: 'saved-end',
      siteId: 'saved-site', destinationName: '保存済み現場', reportId: reporter ? 'report' : null,
      state: complete ? CheckoutReportState.complete : reporter ? CheckoutReportState.partialSignature : CheckoutReportState.missing,
      reporterSignatureSaved: reporter, responsibleSignatureSaved: responsible || complete);

class _Reader implements CheckoutReportResumeRepository {
  CheckoutReportResumeTarget value = _target();
  int reads=0, rechecks=0;
  @override Future<List<CheckoutReportResumeTarget>> loadDay({required String workerId,required DateTime workDate}) async {
    expect(workerId,'worker');expect(workDate,DateTime(2026,10,21));reads++;return [value];
  }
  @override Future<CheckoutReportResumeTarget> revalidate(CheckoutReportResumeTarget target) async {
    expect(target.sourceClockInId,'saved-start');expect(target.clockOutId,'saved-end');
    rechecks++;return value;
  }
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
void main(){
  test('both saved signatures in draft await finalization, not another signature', () {
    expect(checkoutReportStateLabel(_target(reporter:true,responsible:true)),
        'サイン保存済み・確定待ち');
    expect(checkoutReportStateLabel(_target(reporter:true)),
        '現場責任者のサイン待ち');
    expect(checkoutReportStateLabel(_target(reporter:true,complete:true)),
        '日報確定済み');
  });
  testWidgets('returning from a both-signed draft does not request reporter signing', (t) async {
    final reader=_Reader()..value=_target(reporter:true,responsible:true);
    await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>offerCheckoutReportResumeForDay(context,workerId:'worker',
        workDate:DateTime(2026,10,21),repository:reader,opener:(context,target)async{}),
      child:const Text('日付'))))));
    await t.tap(find.text('日付'));await t.pumpAndSettle();
    expect(find.text('サイン保存済み・確定待ち'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('resume-checkout-report-saved-start')));
    await t.pumpAndSettle();
    expect(find.text('サインは保存済みです。日報の確定と給与・請求への反映は未完了です。'),findsOneWidget);
    expect(t.takeException(),isNull);
  });
  testWidgets('calendar action resumes saved day and exact source without re-clocking', (t) async {
    final reader=_Reader();CheckoutReportResumeTarget? opened;
    await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>offerCheckoutReportResumeForDay(context,workerId:'worker',
        workDate:DateTime(2026,10,21),repository:reader,
        opener:(context,target)async{opened=target;reader.value=_target(reporter:true);}),
      child:const Text('日付'))))));
    await t.tap(find.text('日付'));await t.pumpAndSettle();
    expect(find.text('退勤済み・日報未作成'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('resume-checkout-report-saved-start')));await t.pumpAndSettle();
    expect(opened?.workDate,DateTime(2026,10,21));
    expect(opened?.siteId,'saved-site');expect(opened?.sourceClockInId,'saved-start');
    expect(reader.reads,1);expect(reader.rechecks,2);
    expect(find.text('現場責任者のサインがないため、給与に未反映です。'),findsOneWidget);
    expect(t.takeException(),isNull);
  });
  testWidgets('completed report preserves the original saved-report calendar path', (t) async {
    final reader=_Reader()..value=_target(reporter:true,complete:true);
    bool? handled;
    await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{handled=await offerCheckoutReportResumeForDay(context,workerId:'worker',
        workDate:DateTime(2026,10,21),repository:reader);},
      child:const Text('日付'))))));
    await t.tap(find.text('日付'));await t.pumpAndSettle();
    expect(handled,false);expect(find.text('退勤後の日報を作成・再開'),findsNothing);
    expect(reader.rechecks,0);expect(t.takeException(),isNull);
  });
  testWidgets('cancelling resume does not open a report or mutate saved shifts', (t) async {
    final reader=_Reader();var opens=0;
    await t.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()=>offerCheckoutReportResumeForDay(context,workerId:'worker',
        workDate:DateTime(2026,10,21),repository:reader,opener:(context,target)async{opens++;}),
      child:const Text('日付'))))));
    await t.tap(find.text('日付'));await t.pumpAndSettle();
    await t.tapAt(const Offset(5,5));await t.pumpAndSettle();
    expect(opens,0);expect(reader.rechecks,0);expect(t.takeException(),isNull);
  });
}
