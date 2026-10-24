import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/security/security_collector_repository.dart';
import 'package:sk_works/features/security/security_collector_page.dart';

void main() {
  void pause(WidgetTester t) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }
  void resume(WidgetTester t) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  Future<void> settle(WidgetTester t) async {
    // The UI starts work in FakeAsync, while Stream cancellation may complete
    // in the real zone. Drain each of the nested availability/read cleanup
    // boundaries in order before settling animation; never extend the timeout.
    for (var boundary=0;boundary<3;boundary++) {
      await t.pump();
      await t.runAsync(() async { await Future<void>.delayed(Duration.zero); });
    }
    await t.pumpAndSettle();
  }
  Future<void> beginRead(WidgetTester t, void Function(Completer<void>) attachWitness,
      String Function() stages) async {
    // Start the entire repository chain in the real async zone, rather than
    // jumping zones only after nested session/availability work has begun.
    await t.runAsync(() async {
      // Creation AND awaiting belong to this same real zone. A FakeAsync
      // completer would strand this witness even after reads already reached 1.
      final readReached=Completer<void>();
      attachWitness(readReached);
      await t.tap(find.text('再認証して収集記録を表示'));
      await readReached.future.timeout(const Duration(seconds: 2),
        onTimeout: () => throw StateError('Collector read stage not reached: ${stages()}'));
      await Future<void>.delayed(Duration.zero);
    });
  }
  Future<void> readSuccessfully(WidgetTester t, void Function(Completer<void>) attachWitness,
      String Function() stages) async {
    await beginRead(t,attachWitness,stages);
    await settle(t);
  }
  testWidgets('unavailable is not confused with zero records or safety', (t) async {
    final repository = SecurityCollectorRepository(sessionKey: () => 'master/a',
      sessionChanges: const Stream<String?>.empty(), availableCheck: () async => false,
      issueProof: (_) async => throw StateError('not allowed'),
      readWithProof: (_) async => throw StateError('not allowed'));
    await t.pumpWidget(MaterialApp(home: SecurityCollectorPage(repository:repository)));
    await settle(t);
    expect(find.byKey(const ValueKey('collector-password')), findsNothing);
    expect(find.textContaining('未接続または提供準備中'),findsOneWidget);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
  });
  testWidgets('background clears snapshot and password; resumed screen requires fresh read', (t) async {
    var issued=0, reads=0, availableCalls=0;
    late Completer<void> readReached;
    final repository = SecurityCollectorRepository(sessionKey: () => 'master/a',
      sessionChanges: const Stream<String?>.empty(), availableCheck: () async { availableCalls++; return true; },
      issueProof: (_) async { issued++; return 'a'*64; },
      readWithProof: (_) async { reads++;readReached.complete();return {'version':1,'source_provenance':'trusted_collector_observation',
        'coverage':'collector_observations_only','attack_confirmed':false,'events':[]}; });
    await t.pumpWidget(MaterialApp(home: SecurityCollectorPage(repository:repository)));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await readSuccessfully(t,(witness)=>readReached=witness,()=> 'available=$availableCalls issued=$issued reads=$reads');
    expect(reads,1);
    expect(issued,1); expect(find.textContaining('対象範囲の保存記録はありません'),findsOneWidget);
    pause(t); await t.pump();
    // Paused schedulers do not paint a new frame. Do not claim this proves a
    // native app-switcher privacy cover or an immediate background screenshot.
    resume(t); await settle(t);
    expect(issued,1);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
    expect(t.widget<TextField>(find.byKey(const ValueKey('collector-password'))).controller!.text,isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('cancel while obtaining proof never consumes or displays it', (t) async {
    final proof=Completer<String>(); var reads=0;
    final repository=SecurityCollectorRepository(sessionKey:()=> 'master/a',
      sessionChanges:const Stream<String?>.empty(),availableCheck:() async=>true,
      issueProof:(_)=>proof.future,readWithProof:(_) async { reads++; return {}; });
    await t.pumpWidget(MaterialApp(home:SecurityCollectorPage(repository:repository)));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await t.tap(find.text('再認証して収集記録を表示')); await t.pump(); await t.pump();
    await t.tap(find.text('表示を取り消す')); await settle(t);
    proof.complete('a'*64); await settle(t); expect(reads,0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('session replacement clears displayed records and remains locked after return', (t) async {
    final changes=StreamController<String?>.broadcast(sync:true);
    String? key='master/a';
    var issued=0,reads=0,availableCalls=0;
    late Completer<void> readReached;
    final repository=SecurityCollectorRepository(sessionKey:()=>key,sessionChanges:changes.stream,
      availableCheck:() async {availableCalls++;return true;},issueProof:(_) async {issued++;return 'a'*64;},
      readWithProof:(_) async {reads++;readReached.complete();return {'version':1,'source_provenance':'trusted_collector_observation',
        'coverage':'collector_observations_only','attack_confirmed':false,'events':[]};});
    await t.pumpWidget(MaterialApp(home:SecurityCollectorPage(repository:repository)));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await readSuccessfully(t,(witness)=>readReached=witness,()=> 'available=$availableCalls issued=$issued reads=$reads');
    expect(issued,1);expect(reads,1);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsOneWidget);
    key='other/b';changes.add(key);await t.pump();
    key='master/a';changes.add(key);await settle(t);
    expect(find.byKey(const ValueKey('collector-password')),findsNothing);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
    expect(find.textContaining('本人確認が失効しました'),findsOneWidget);
    await t.pumpWidget(const SizedBox());await changes.close();
  });
  testWidgets('a response arriving while paused is discarded before resumed display', (t) async {
    late Completer<void> readReached;
    late Completer<dynamic> response;
    var reads=0,issued=0;
    final repository=SecurityCollectorRepository(sessionKey:()=> 'master/a',
      sessionChanges:const Stream<String?>.empty(),availableCheck:() async=>true,
      issueProof:(_) async {issued++;return 'a'*64;},
      readWithProof:(_) {reads++;readReached.complete();return response.future;});
    await t.pumpWidget(MaterialApp(home:SecurityCollectorPage(repository:repository)));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await beginRead(t,(witness){readReached=witness;response=Completer<dynamic>();},
      ()=> 'issued=$issued reads=$reads');
    pause(t);
    await t.runAsync(() async {
      response.complete({'version':1,'source_provenance':'trusted_collector_observation',
        'coverage':'collector_observations_only','attack_confirmed':false,'events':[]});
      await Future<void>.delayed(Duration.zero);
    });
    resume(t);
    await settle(t);
    expect(issued,1);expect(reads,1);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
    expect(t.widget<TextField>(find.byKey(const ValueKey('collector-password'))).controller!.text,isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('async same-user session A-B-A clears already displayed records permanently', (t) async {
    final events=StreamController<String?>.broadcast();
    String? key='master/session-a';late Completer<void> readReached;
    var reads=0;
    final repository=SecurityCollectorRepository(sessionKey:()=>key,sessionChanges:events.stream,
      availableCheck:() async=>true,issueProof:(_) async=>'a'*64,
      readWithProof:(_) async {reads++;readReached.complete();return {'version':1,
        'source_provenance':'trusted_collector_observation','coverage':'collector_observations_only',
        'attack_confirmed':false,'events':[]};});
    await t.pumpWidget(MaterialApp(home:SecurityCollectorPage(repository:repository)));
    await settle(t);
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await readSuccessfully(t,(witness)=>readReached=witness,()=> 'reads=$reads');
    expect(find.textContaining('対象範囲の保存記録はありません'),findsOneWidget);
    key='master/session-b';events.add(key);
    key='master/session-a';events.add(key); // restore BEFORE the async delivery
    await settle(t);
    expect(find.byKey(const ValueKey('collector-password')),findsNothing);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
    expect(find.textContaining('本人確認が失効しました'),findsOneWidget);
    expect(reads,1);
    await t.pumpWidget(const SizedBox());await events.close();
  });
}
