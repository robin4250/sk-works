import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _InitialLoginFlow extends StatefulWidget {
  const _InitialLoginFlow(this.completion, this.onDispose);
  final Future<void> completion;
  final VoidCallback onDispose;
  @override
  State<_InitialLoginFlow> createState() => _InitialLoginFlowState();
}
class _InitialLoginFlowState extends State<_InitialLoginFlow> {
  bool _completed = false;
  @override
  void initState() {
    super.initState();
    widget.completion.then((_) { if (mounted) setState(() => _completed = true); });
  }
  @override
  void dispose() { widget.onDispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) =>
      Text(_completed ? 'registration completed' : 'password update pending');
}

const owner = '40000000-0000-0000-0000-000000000001';
const other = '40000000-0000-0000-0000-000000000002';
const sid = '40000000-0000-0000-0000-000000000003';
Session session(String uid, {String sessionId = sid, String? accessToken, int generation = 1}) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'sub':uid,'session_id':sessionId,'iat':generation}))).replaceAll('=', '');
  return Session.fromJson({'access_token':accessToken ?? 'e30.$payload.c2ln',
    'refresh_token':'fixture','token_type':'bearer','user':{'id':uid,'aud':'authenticated',
    'app_metadata':{},'user_metadata':{},'created_at':'2026-01-01T00:00:00Z'}})!;
}
AuthState change(String? uid, {String sessionId = sid, AuthChangeEvent event = AuthChangeEvent.signedIn, int generation = 1}) =>
    AuthState(event, uid == null ? null : session(uid, sessionId:sessionId, generation:generation));

void main() {
  testWidgets('first sign-in preserves pending OTP/onboarding completion',
      (tester) async {
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    final completion = Completer<void>();
    var disposed = 0;
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      authChanges: changes.stream,
      child: MaterialApp(home: _InitialLoginFlow(
        completion.future, () => disposed++)),
    ));
    changes.add(change(owner));
    await tester.idle();
    await tester.pump();
    expect(find.text('password update pending'), findsOneWidget);
    expect(disposed, 0);
    completion.complete();
    await tester.idle();
    await tester.pump();
    expect(find.text('registration completed'), findsOneWidget);
    expect(disposed, 0);
  });
  for (final actor in <String?>[null, other, owner]) {
    testWidgets('identity $actor destroys pushed private pages and Navigator',
        (tester) async {
      final changes = StreamController<AuthState>();
      addTearDown(changes.close);
      final navigator = GlobalKey<NavigatorState>();
      var disposed = 0;
      await tester.pumpWidget(AuthenticatedNavigationBoundary(
        initialSession: session(owner), authChanges: changes.stream,
        child: MaterialApp(navigatorKey: navigator,
          home: const Scaffold(body: Text('home'))),
      ));
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => _PrivatePage(() => disposed++))));
      await tester.pumpAndSettle();
      final oldNavigator = navigator.currentState;
      expect(find.text('private file'), findsOneWidget);
      changes.add(change(actor, sessionId: actor == owner ? other : sid));
      await tester.idle();
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
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialSession: session(owner), authChanges: changes.stream,
      child: MaterialApp(navigatorKey: navigator,
        home: const Scaffold(body: Text('home'))),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => _PrivatePage(() {}))));
    await tester.pumpAndSettle();
    final current = navigator.currentState;
    changes.add(change(owner, event: AuthChangeEvent.tokenRefreshed, generation:2));
    await tester.idle();
    await tester.pump();
    expect(find.text('private file'), findsOneWidget);
    expect(navigator.currentState, same(current));
  });

  testWidgets('auth stream failure destroys routes and does not show stale UI',
      (tester) async {
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialSession: session(owner), authChanges: changes.stream,
      child: const MaterialApp(home: Text('private file')),
    ));
    changes.addError(StateError('unavailable'));
    await tester.idle();
    await tester.pump();
    expect(find.text('private file'), findsNothing);
    expect(find.textContaining('確認できません'), findsOneWidget);
    changes.add(change(owner));
    await tester.idle();
    await tester.pump();
    expect(find.text('private file'), findsNothing);
    await tester.pump();
    expect(find.text('private file'), findsOneWidget);
  });

  testWidgets('rapid identity return cannot resurrect the old private route',
      (tester) async {
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialSession: session(owner), authChanges: changes.stream,
      child: MaterialApp(navigatorKey: navigator,
        home: const Scaffold(body: Text('home'))),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => _PrivatePage(() {}))));
    await tester.pumpAndSettle();
    changes.add(change(null)); changes.add(change(owner));
    await tester.idle();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('private file'), findsNothing);
    expect(navigator.currentState!.canPop(), false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('malformed session fails closed and cannot use onboarding exception', (tester) async {
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      authChanges: changes.stream,
      child: const MaterialApp(home: Text('private file')),
    ));
    changes.add(AuthState(AuthChangeEvent.signedIn, session(owner, accessToken:'malformed')));
    await tester.idle(); await tester.pump();
    expect(find.text('private file'), findsNothing);
    expect(find.textContaining('確認できません'), findsOneWidget);
    changes.add(change(owner));
    await tester.idle(); await tester.pump();
    expect(find.text('private file'), findsNothing);
    await tester.pump();
    expect(find.text('private file'), findsOneWidget);
  });

  testWidgets('same actor session return cannot resurrect private routes', (tester) async {
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialSession: session(owner), authChanges: changes.stream,
      child: MaterialApp(navigatorKey: navigator, home: const Text('home')),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => _PrivatePage(() {}))));
    await tester.pumpAndSettle();
    changes.add(change(owner, sessionId: other));
    changes.add(change(owner));
    await tester.idle(); await tester.pump(); await tester.pumpAndSettle();
    expect(find.text('private file'), findsNothing);
    expect(navigator.currentState!.canPop(), false);
  });

  testWidgets('initialSession restoration does not use first-signin exception', (tester) async {
    final changes = StreamController<AuthState>();
    addTearDown(changes.close);
    var disposed = 0;
    final completion = Completer<void>();
    await tester.pumpWidget(AuthenticatedNavigationBoundary(
      authChanges: changes.stream,
      child: MaterialApp(home: _InitialLoginFlow(completion.future, () => disposed++)),
    ));
    changes.add(change(owner, event: AuthChangeEvent.initialSession));
    await tester.idle(); await tester.pump();
    expect(disposed, 1);
    expect(find.text('password update pending'), findsNothing);
    await tester.pump();
    completion.complete();
    await tester.idle(); await tester.pump();
  });

}
