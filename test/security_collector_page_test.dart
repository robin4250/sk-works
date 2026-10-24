import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/security/security_collector_repository.dart';
import 'package:sk_works/features/security/security_collector_page.dart';

void main() {
  testWidgets('unavailable is not confused with zero records or safety', (t) async {
    final repository = SecurityCollectorRepository(sessionKey: () => 'master/a',
      sessionChanges: const Stream<void>.empty(), availableCheck: () async => false,
      issueProof: (_) async => throw StateError('not allowed'),
      readWithProof: (_) async => throw StateError('not allowed'));
    await t.pumpWidget(MaterialApp(home: SecurityCollectorPage(repository:repository)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('collector-password')), findsNothing);
    expect(find.textContaining('未接続または提供準備中'),findsOneWidget);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
  });
  testWidgets('background clears snapshot and password; resumed screen requires fresh read', (t) async {
    var issued=0;
    final repository = SecurityCollectorRepository(sessionKey: () => 'master/a',
      sessionChanges: const Stream<void>.empty(), availableCheck: () async => true,
      issueProof: (_) async { issued++; return 'a'*64; },
      readWithProof: (_) async => {'version':1,'source_provenance':'trusted_collector_observation',
        'coverage':'collector_observations_only','attack_confirmed':false,'events':[]});
    await t.pumpWidget(MaterialApp(home: SecurityCollectorPage(repository:repository)));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await t.tap(find.text('再認証して収集記録を表示')); await t.pumpAndSettle();
    expect(issued,1); expect(find.textContaining('対象範囲の保存記録はありません'),findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await t.pump();
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await t.pumpAndSettle();
    expect(issued,1);
    expect(t.widget<TextField>(find.byKey(const ValueKey('collector-password'))).controller!.text,isEmpty);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('cancel while obtaining proof never consumes or displays it', (t) async {
    final proof=Completer<String>(); var reads=0;
    final repository=SecurityCollectorRepository(sessionKey:()=> 'master/a',
      sessionChanges:const Stream<void>.empty(),availableCheck:() async=>true,
      issueProof:(_)=>proof.future,readWithProof:(_) async { reads++; return {}; });
    await t.pumpWidget(MaterialApp(home:SecurityCollectorPage(repository:repository)));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await t.tap(find.text('再認証して収集記録を表示')); await t.pump(); await t.pump();
    await t.tap(find.text('表示を取り消す')); await t.pumpAndSettle();
    proof.complete('a'*64); await t.pumpAndSettle(); expect(reads,0);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('session replacement clears displayed records and remains locked after return', (t) async {
    final changes=StreamController<void>.broadcast(sync:true);
    String? key='master/a';
    final repository=SecurityCollectorRepository(sessionKey:()=>key,sessionChanges:changes.stream,
      availableCheck:() async=>true,issueProof:(_) async=>'a'*64,
      readWithProof:(_) async=>{'version':1,'source_provenance':'trusted_collector_observation',
        'coverage':'collector_observations_only','attack_confirmed':false,'events':[]});
    await t.pumpWidget(MaterialApp(home:SecurityCollectorPage(repository:repository)));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('collector-password')),'password');
    await t.tap(find.text('再認証して収集記録を表示')); await t.pumpAndSettle();
    expect(find.textContaining('対象範囲の保存記録はありません'),findsOneWidget);
    key='other/b';changes.add(null);await t.pump();
    key='master/a';changes.add(null);await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('collector-password')),findsNothing);
    expect(find.textContaining('対象範囲の保存記録はありません'),findsNothing);
    expect(find.textContaining('本人確認が失効しました'),findsOneWidget);
    await t.pumpWidget(const SizedBox());await changes.close();
  });
}
