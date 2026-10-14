import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/security/security_actor_boundary.dart';

void main() {
  for (final nextActor in <String?>['other', null]) {
    testWidgets('actor change $nextActor removes protected record immediately',
        (tester) async {
      final actors = StreamController<String?>();
      addTearDown(actors.close);
      await tester.pumpWidget(MaterialApp(
        home: SecurityActorBoundary(
          initialActor: 'master',
          actorChanges: actors.stream,
          child: const Text('protected record'),
        ),
      ));
      expect(find.text('protected record'), findsOneWidget);
      actors.add(nextActor);
      await tester.pump();
      expect(find.text('protected record'), findsNothing);
      expect(find.textContaining('本人確認が失効'), findsOneWidget);
      actors.add('master');
      await tester.pump();
      expect(find.text('protected record'), findsNothing);
    });
  }

  testWidgets('same-actor token refresh preserves the protected view',
      (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    await tester.pumpWidget(MaterialApp(
      home: SecurityActorBoundary(
        initialActor: 'master',
        actorChanges: actors.stream,
        child: const Text('protected record'),
      ),
    ));
    actors.add('master');
    await tester.pump();
    expect(find.text('protected record'), findsOneWidget);
  });

  testWidgets('auth stream failure removes the protected view', (tester) async {
    final actors = StreamController<String?>();
    addTearDown(actors.close);
    await tester.pumpWidget(MaterialApp(
      home: SecurityActorBoundary(
        initialActor: 'master',
        actorChanges: actors.stream,
        child: const Text('protected record'),
      ),
    ));
    actors.addError(StateError('unavailable'));
    await tester.pump();
    expect(find.text('protected record'), findsNothing);
  });
}
