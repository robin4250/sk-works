import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/expenses/expense_receipt_preview.dart';

Uint8List fixtureBytes(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  tearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  Future<void> mount(WidgetTester tester, StreamController<String?> actors,
      Future<Uint8List> Function(String) loader,
      {Duration lifetime = const Duration(seconds: 300)}) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ExpenseReceiptPreview(objectPath: 'fixture/receipt.jpg',
        initialActor: 'owner', actorChanges: actors.stream, bytesLoader: loader,
        previewLifetime: lifetime, imageBuilder: (bytes) => Text('image:${utf8.decode(bytes)}')))));
    await tester.pump();
  }

  for (final actor in <String?>[null, 'other']) {
    testWidgets('logout or actor $actor discards image and rejects late result',
        (tester) async {
      final actors = StreamController<String?>();
      addTearDown(actors.close);
      final result = Completer<Uint8List>();
      await mount(tester, actors, (_) => result.future);
      actors.add(actor);
      await tester.pump();
      result.complete(fixtureBytes('old-receipt'));
      await tester.pump();
      expect(find.textContaining('image:'), findsNothing);
      actors.add('owner');
      await tester.pump();
      expect(find.textContaining('image:'), findsNothing);
      expect(find.textContaining('本人確認'), findsOneWidget);
    });
  }

  testWidgets('same actor refresh clears old image and handles revoked access',
      (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    var calls = 0;
    await mount(tester, actors, (_) async {
      if (++calls == 1) return fixtureBytes('first');
      throw StateError('forbidden');
    });
    expect(find.text('image:first'), findsOneWidget);
    actors.add('owner');
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.textContaining('image:'), findsNothing);
    expect(find.textContaining('取得できません'), findsOneWidget);
  });

  testWidgets('authenticated preview expires locally without reusing old image', (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    await mount(tester, actors, (_) async => fixtureBytes('temporary'),
        lifetime: const Duration(seconds: 2));
    expect(find.text('image:temporary'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('image:'), findsNothing);
    expect(find.textContaining('取得できません'), findsOneWidget);
  });

  testWidgets('background removes image and resume requires fresh authorization',
      (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    var calls = 0;
    await mount(tester, actors, (_) async => fixtureBytes('${++calls}'));
    expect(find.text('image:1'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.textContaining('image:'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('image:2'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('auth errors discard an already loaded image', (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    await mount(tester, actors, (_) async => fixtureBytes('fixture'));
    expect(find.text('image:fixture'), findsOneWidget);
    actors.addError(StateError('auth_unavailable'));
    await tester.pump();
    expect(find.textContaining('image:'), findsNothing);
    expect(find.textContaining('本人確認'), findsOneWidget);
  });

  testWidgets('mounting while inactive never requests the receipt until resume',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    var calls = 0;
    await mount(tester, actors, (_) async { calls++; return fixtureBytes('fresh'); });
    expect(calls, 0);
    expect(find.textContaining('image:'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('image:fresh'), findsOneWidget);
  });
}
