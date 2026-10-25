import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/gps_work_schedule_dialog.dart';
void main(){
 testWidgets('one GPS settings dialog shows both times with help folded',(tester)async{
  GpsWorkScheduleDraft? result;
  await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(onPressed:()async{
   result=await showGpsWorkScheduleDialog(context);
  },child:const Text('settings'))))));
  await tester.tap(find.text('settings'));await tester.pumpAndSettle();
  expect(find.text('出勤時刻'),findsOneWidget);expect(find.text('退勤確認時刻'),findsOneWidget);
  expect(find.text('08:00'),findsOneWidget);expect(find.text('17:00'),findsOneWidget);
  await tester.tap(find.text('保存'));await tester.pumpAndSettle();
  expect(result?.weekdays,[1,2,3,4,5]);expect(result?.clockInDatabase,'08:00:00');expect(result?.checkoutDatabase,'17:00:00');
 });
 testWidgets('overnight reminder clearly displays next day',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:GpsWorkScheduleDialog(
   initialClockIn:TimeOfDay(hour:22,minute:0),initialCheckoutReminder:TimeOfDay(hour:6,minute:0)))));
  expect(find.text('06:00（翌日）'),findsOneWidget);
 });
 testWidgets('same clock-in and reminder time cannot silently become a 24h shift',(tester)async{
  await tester.pumpWidget(const MaterialApp(home:Scaffold(body:GpsWorkScheduleDialog(
   initialClockIn:TimeOfDay(hour:8,minute:0),initialCheckoutReminder:TimeOfDay(hour:8,minute:0)))));
  final button=tester.widget<FilledButton>(find.widgetWithText(FilledButton,'保存'));expect(button.onPressed,isNull);
 });
}
