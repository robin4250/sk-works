import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/qualifications/qualification_photo_review_entry.dart';

void main() {
  late StreamController<Object?> changes;
  late Object? scope;
  late List<Map<String, dynamic>> rows;
  late Future<List<Map<String, dynamic>>> Function() load;
  late int opens;

  setUp(() {
    changes = StreamController<Object?>.broadcast(sync: true);
    scope = ('owner', 'token');
    rows = [
      {'requested_by': 'owner', 'status': 'pending', 'can_review': true},
    ];
    load = () async => rows;
    opens = 0;
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: QualificationPhotoReviewEntry(
        loadPending: () => load(), scope: () => scope,
        scopeChanges: changes.stream, onOpen: () async { opens++; },
      ),
    )));
    await tester.pump();
  }

  tearDown(() async { await changes.close(); });

  testWidgets('own pending marked reviewable opens existing review action', (tester) async {
    await show(tester);
    expect(find.text('承認できる申請 1件'), findsOneWidget);
    await tester.tap(find.text('資格写真の承認待ち'));
    await tester.pump();
    expect(opens, 1);
  });

  testWidgets('general actor and completed rows never expose an entry', (tester) async {
    rows = [
      {'status': 'pending', 'can_review': false},
      {'status': 'approved', 'can_review': true},
    ];
    await show(tester);
    expect(find.text('資格写真の承認待ち'), findsNothing);
    expect(opens, 0);
  });

  testWidgets('backend failure fails closed', (tester) async {
    load = () async => throw StateError('unavailable');
    await show(tester);
    expect(find.text('資格写真の承認待ち'), findsNothing);
  });

  testWidgets('scope ABA discards a late pending response', (tester) async {
    final reply = Completer<List<Map<String, dynamic>>>();
    load = () => reply.future;
    await show(tester);
    changes.add(null);
    changes.add('original returned');
    reply.complete(rows);
    await tester.pump();
    expect(find.text('資格写真の承認待ち'), findsNothing);
  });

  testWidgets('token change without stream delivery prevents opening', (tester) async {
    await show(tester);
    scope = ('owner', 'new-token');
    await tester.tap(find.text('資格写真の承認待ち'));
    await tester.pump();
    expect(opens, 0);
    expect(find.text('資格写真の承認待ち'), findsNothing);
  });

  testWidgets('background hides entry and resumed read revalidates it', (tester) async {
    await show(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('資格写真の承認待ち'), findsNothing);
    rows = [];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('資格写真の承認待ち'), findsNothing);
  });

  testWidgets('initial background mount does not read or expose requests', (tester) async {
    var reads = 0;
    load = () async { reads++; return rows; };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await show(tester);
    expect(reads, 0);
    expect(find.text('資格写真の承認待ち'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('資格写真の承認待ち'), findsOneWidget);
  });

  testWidgets('disposing before response returns exposes nothing', (tester) async {
    final reply = Completer<List<Map<String, dynamic>>>();
    load = () => reply.future;
    await show(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    reply.complete(rows);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
