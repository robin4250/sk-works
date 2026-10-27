import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/security/security_collector_repository.dart';
import 'package:sk_works/features/security/security_notice_page.dart';
import 'package:sk_works/features/security/security_notice_repository.dart';

void main(){
  test('explicit SQL rejection differs from unknown acknowledgement',() async {
    final events=StreamController<String?>.broadcast(sync:true);
    final base=SecurityCollectorRepository(sessionKey:()=> 'user/session',availableCheck:()async=>true,
      issueProof:(_)async=>'a'*64,readWithProof:(_)async=>{},sessionChanges:events.stream);
    var definite=true;
    final repo=SecurityNoticeRepository(collector:base,readRpc:(_)async=>{},updateRpc:(cmd,proof)async {
      if(definite) throw const PostgrestException(message:'notice_changed_reload',code:'40001');
      throw StateError('transport outcome unknown');
    });
    final cmd=SecurityNoticeCommand(eventId:'00000000-0000-4000-8000-000000000001',action:'read',reason:'',revision:1,commandId:'00000000-0000-4000-8000-000000000002');
    await expectLater(repo.update(cmd,'fixture'),throwsA(isA<SecurityNoticeRejected>()));
    definite=false;await expectLater(repo.update(cmd,'fixture'),throwsA(isA<StateError>()));
    await events.close();
  });
  testWidgets('unconfirmed update retries the same command and displays saved status', (tester) async {
    final events=StreamController<String?>.broadcast(sync:true);addTearDown(events.close);
    var actor='user/session';var readAt=false;var calls=0, availabilityCalls=0, proofCalls=0, readCalls=0;final commandIds=<String>[];
    final base=SecurityCollectorRepository(sessionKey:()=>actor,availableCheck:()async{availabilityCalls++;return true;},
      issueProof:(_)async{proofCalls++;return 'a'*64;},readWithProof:(_)async=>{},sessionChanges:events.stream);
    final repo=SecurityNoticeRepository(collector:base,
      readRpc:(_)async{readCalls++;return {'version':1,'coverage':'collector_observations_only','attack_confirmed':false,'capacity_gaps':1,'events':[
        {'event_id':'00000000-0000-4000-8000-000000000001','event_kind':'current_lure_touched','generation':1,
         'occurred_at':'2026-10-27T00:00:00Z','available_at':'2026-10-27T00:00:01Z',
         'read_at':readAt?'2026-10-27T00:00:02Z':null,'review_state':'unreviewed','review_reason':null,
         'revision':readAt?2:1,'scope':'decoy_generation_only','state':'observed'}]};},
      updateRpc:(cmd,_)async{calls++;commandIds.add(cmd.commandId);if(calls==1)throw StateError('unknown result');readAt=true;return {'event_id':cmd.eventId,'revision':cmd.revision+1,'replayed':true};});
    await tester.pumpWidget(MaterialApp(home:SecurityNoticePage(repository:repo)));
    await tester.enterText(find.byKey(const ValueKey('notice-password')),'fixture');
    await tester.tap(find.text('本人確認して一覧を表示'));await tester.pump();
    await tester.runAsync(() async {await Future<void>.delayed(const Duration(milliseconds:50));});await tester.pump();
    for(var i=0;i<50 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;i++){await tester.pump(const Duration(milliseconds:100));}
    await tester.pump();expect(find.byType(LinearProgressIndicator),findsNothing,reason:'一覧取得を完了できません: available=$availabilityCalls proof=$proofCalls read=$readCalls');
    expect(find.textContaining('未対応'),findsOneWidget);expect(find.textContaining('記録できなかった観測が1件'),findsOneWidget);
    await tester.ensureVisible(find.text('確認済みにする'));await tester.pumpAndSettle();
    await tester.tap(find.text('確認済みにする'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('notice-password')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('notice-password')),'fixture');
    await tester.tap(find.text('同じ操作を再確認'));await tester.pump();
    for(var i=0;i<25 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;i++){await tester.runAsync(() async {await Future<void>.delayed(const Duration(milliseconds:20));});await tester.pump(const Duration(milliseconds:100));}
    expect(find.byType(LinearProgressIndicator),findsNothing,reason:'対応結果を確認できません: available=$availabilityCalls proof=$proofCalls read=$readCalls update=$calls');await tester.pumpAndSettle();
    expect(find.textContaining('結果を確認できません'),findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('notice-password')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('notice-password')),'fixture');
    await tester.tap(find.text('同じ操作を再確認'));await tester.pump();
    for(var i=0;i<25 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;i++){await tester.runAsync(() async {await Future<void>.delayed(const Duration(milliseconds:20));});await tester.pump(const Duration(milliseconds:100));}
    expect(find.byType(LinearProgressIndicator),findsNothing,reason:'対応結果を確認できません: available=$availabilityCalls proof=$proofCalls read=$readCalls update=$calls');await tester.pumpAndSettle();
    expect(commandIds.length,2);expect(commandIds[0],commandIds[1]);
    expect(find.text('確認済み'),findsOneWidget);
    actor='other/session';events.add(actor);await tester.pumpAndSettle();
    expect(find.textContaining('本人確認が失効'),findsOneWidget);
    expect(find.text('確認済み'),findsNothing);
  });
}
