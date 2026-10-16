import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/authenticated_navigation_boundary.dart';

class _PrivatePage extends StatefulWidget {
  const _PrivatePage(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_PrivatePage> createState() => _PrivatePageState();
}
class _PrivatePageState extends State<_PrivatePage> {
  @override
  void dispose() { widget.onDispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('private file'));
}

void main() {
  for (final actor in <String?>[null, 'other']) {
    testWidgets('identity $actor destroys pushed private pages and Navigator',
        (tester) async {
      final changes = StreamController<String?>();
      addTearDown(changes.close);
      final navigator = GlobalKey<NavigatorState>();
      var disposed = 0;
      await tester.pumpWidget(AuthenticatedNavigationBoundary(
        initialActor: 'owner', actorChanges: changes.stream,
        child: MaterialApp(navigatorKey: navigator,
          home: const Scaffold(body: Text('home'))),
      ));
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => _PrivatePage(() => disposed++))));
      await tester.pumpAndSettle();
      final oldNavigator = navigator.currentState;
      expect(find.text('private file'), findsOneWidget);
      changes.add(actor);
      await tester.pump();
      expect(find.text('private file'), findsNothing);
      expect(disposed, 1);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(navigator.currentState, isNot(same(oldNavigator)));
      expect(navigator.currentState!.canPop(), false);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('same actor refresh retains legitimate navigation', (tester) async {
    final changes = StreamController<String?>();
    addTearDown(changes.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialActor: 'owner', actorChanges: changes.stream,
      child: MaterialApp(navigatorKey: navigator,
        home: const Scaffold(body: Text('home'))),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => _PrivatePage(() {}))));
    await tester.pumpAndSettle();
    final current = navigator.currentState;
    changes.add('owner');
    await tester.pump();
    expect(find.text('private file'), findsOneWidget);
    expect(navigator.currentState, same(current));
  });

  testWidgets('auth stream failure destroys routes and does not show stale UI',
      (tester) async {
    final changes = StreamController<String?>();
    addTearDown(changes.close);
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialActor: 'owner', actorChanges: changes.stream,
      child: const MaterialApp(home: Text('private file')),
    ));
    changes.addError(StateError('unavailable'));
    await tester.pump();
    expect(find.text('private file'), findsNothing);
    expect(find.textContaining('確認できません'), findsOneWidget);
    changes.add('owner');
    await tester.pump();
    expect(find.text('private file'), findsNothing);
    await tester.pump();
    expect(find.text('private file'), findsOneWidget);
  });

  testWidgets('rapid identity return cannot resurrect the old private route',
      (tester) async {
    final changes = StreamController<String?>();
    addTearDown(changes.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialActor: 'owner', actorChanges: changes.stream,
      child: MaterialApp(navigatorKey: navigator,
        home: const Scaffold(body: Text('home'))),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => _PrivatePage(() {}))));
    await tester.pumpAndSettle();
    changes.add(null); changes.add('owner');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('private file'), findsNothing);
    expect(navigator.currentState!.canPop(), false);
    expect(tester.takeException(), isNull);
  });
}
