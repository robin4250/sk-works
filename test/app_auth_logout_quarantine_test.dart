import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'package:sk_works/features/auth/authenticated_navigation_boundary.dart';
import 'app_auth_mutation_gateway_test.dart' as fixture;

class _PrivatePage extends StatefulWidget {
  const _PrivatePage(this.disposed);
  final VoidCallback disposed;
  @override
  State<_PrivatePage> createState() => _PrivatePageState();
}
class _PrivatePageState extends State<_PrivatePage> {
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('private original file'));
  @override
  void dispose() { widget.disposed(); super.dispose(); }
}
Future<void> drain(WidgetTester tester) async {
  for(var i=0;i<8;i++) {
    await tester.runAsync(() async { await Future<void>.delayed(Duration.zero); });
    await tester.pump();
  }
}
Future<void> mount(WidgetTester tester, fixture.Wire w, GlobalKey<NavigatorState> navigator) =>
    tester.pumpWidget(AuthenticatedNavigationBoundary(
      initialSession:w.client.auth.currentSession,authChanges:w.client.auth.onAuthStateChange,
      mutationGateway:w.auth,child:MaterialApp(navigatorKey:navigator,
        home:const Scaffold(body:Text('fresh root')))));
Future<void> cleanup(WidgetTester tester, fixture.Wire w) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => w.client.dispose());
}
void main() {
  testWidgets('logout intent destroys private Navigator before stalled SDK mutation completes', (tester) async {
    final w=fixture.Wire();
    try {
      await tester.runAsync(() => w.seed());
      final navigator=GlobalKey<NavigatorState>();
      await mount(tester,w,navigator);
      var disposed=0;
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder:(_)=>_PrivatePage(()=>disposed++))));
      await tester.pumpAndSettle();
      final oldNavigator=navigator.currentState;
      final loginReply=Completer<http.Response>();
      final logoutReply=Completer<http.Response>();
      final events=<AuthState>[];
      final observer=w.client.auth.onAuthStateChange.listen(events.add);
      w.respond=(request)=>request.url.path.endsWith('/logout') ? logoutReply.future : loginReply.future;
      final login=w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic');
      final rejected=expectLater(login,throwsStateError);
      await drain(tester);
      expect(w.calls,hasLength(1));
      final logout=w.auth.signOut();
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.pending);
      await tester.pump();
      expect(disposed,1);
      expect(find.text('private original file'),findsNothing);
      expect(navigator.currentState,isNull);
      expect(find.text('ログアウト状態を確認しています。'),findsOneWidget);
      await tester.pump(const Duration(seconds:20));
      expect(find.text('fresh root'),findsNothing); // No timer releases quarantine.
      loginReply.complete(fixture.Wire.json(fixture.session(sessionId:fixture.nextSid)));
      await drain(tester); await rejected;
      expect(events.any((e)=>e.event==AuthChangeEvent.signedIn && e.session!=null),true);
      expect(w.calls.where((r)=>r.url.path.endsWith('/logout')),hasLength(1));
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.pending);
      expect(find.text('fresh root'),findsNothing);
      logoutReply.complete(http.Response('',204));
      await drain(tester); await logout;
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.clear);
      expect(w.client.auth.currentSession,isNull);
      expect(find.text('fresh root'),findsOneWidget);
      expect(navigator.currentState,isNot(same(oldNavigator)));
      expect(navigator.currentState!.canPop(),false);
      await tester.runAsync(observer.cancel);
    } finally { await cleanup(tester,w); }
  });

  testWidgets('SDK logout failure stays blocked across raw signin and offers safe local retry', (tester) async {
    final w=fixture.Wire();
    try {
      await tester.runAsync(() => w.seed());
      final navigator=GlobalKey<NavigatorState>();
      await mount(tester,w,navigator);
      final reply=Completer<http.Response>();
      w.respond=(_)=>reply.future;
      final logout=w.auth.signOut();
      final rejected=expectLater(logout,throwsA(isA<AuthException>()));
      await drain(tester);
      reply.complete(http.Response('{"message":"unavailable"}',503,headers:{'content-type':'application/json'}));
      await drain(tester); await rejected;
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.failed);
      expect(find.text('fresh root'),findsNothing);
      expect(find.text('ログアウトを再試行'),findsOneWidget);
      await expectLater(w.onboarding.signInWithEmail(email:'fixture@example.invalid',password:'synthetic'),throwsStateError);
      // A raw SDK writer is outside ownership, but cannot clear the UI fence.
      w.respond=(_) async=>fixture.Wire.json(fixture.session(sessionId:fixture.nextSid));
      await tester.runAsync(() => w.client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic'));
      await tester.pump();
      expect(find.text('fresh root'),findsNothing);
      w.respond=(_) async=>http.Response('',204);
      await tester.tap(find.text('ログアウトを再試行'));
      await drain(tester);
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.clear);
      expect(w.client.auth.currentSession,isNull);
      expect(find.text('fresh root'),findsOneWidget);
    } finally { await cleanup(tester,w); }
  });

  testWidgets('late SDK signin during logout confirmation cannot release quarantine', (tester) async {
    final w=fixture.Wire();
    try {
      await tester.runAsync(() => w.seed());
      final navigator=GlobalKey<NavigatorState>();
      await mount(tester,w,navigator);
      final reply=Completer<http.Response>();
      w.respond=(_)=>reply.future;
      final logout=w.auth.signOut();
      final rejected=expectLater(logout,throwsStateError);
      await drain(tester);
      expect(w.client.auth.currentSession,isNull);
      w.respond=(request)=>request.url.path.endsWith('/logout') ? reply.future
          : Future.value(fixture.Wire.json(fixture.session(sessionId:fixture.nextSid)));
      await tester.runAsync(() => w.client.auth.signInWithPassword(email:'fixture@example.invalid',password:'synthetic'));
      reply.complete(http.Response('',204));
      await drain(tester); await rejected;
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.failed);
      expect(w.client.auth.currentSession?.refreshToken,'synthetic-${fixture.nextSid}');
      expect(find.text('fresh root'),findsNothing);
      expect(w.calls,hasLength(2)); // Only explicit logout and raw external login; no rollback/retry.
    } finally { await cleanup(tester,w); }
  });

  testWidgets('remount while logout hangs reads quarantine snapshot before rendering child', (tester) async {
    final w=fixture.Wire();
    try {
      await tester.runAsync(() => w.seed());
      final reply=Completer<http.Response>();
      w.respond=(_)=>reply.future;
      final logout=w.auth.signOut();
      await drain(tester);
      await mount(tester,w,GlobalKey<NavigatorState>());
      expect(find.text('fresh root'),findsNothing);
      expect(find.text('ログアウト状態を確認しています。'),findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester,w,GlobalKey<NavigatorState>());
      expect(find.text('fresh root'),findsNothing);
      reply.complete(http.Response('',204));
      await drain(tester); await logout;
      expect(find.text('fresh root'),findsOneWidget);
    } finally { await cleanup(tester,w); }
  });

  testWidgets('retry after failed server request with no local session needs no stale token resend', (tester) async {
    final w=fixture.Wire();
    try {
      await tester.runAsync(() => w.seed());
      await mount(tester,w,GlobalKey<NavigatorState>());
      w.respond=(_) async=>http.Response('{"message":"unavailable"}',503,headers:{'content-type':'application/json'});
      final failed=expectLater(w.auth.signOut(),throwsA(isA<AuthException>()));
      await drain(tester); await failed;
      expect(w.client.auth.currentSession,isNull);
      final requests=w.calls.length;
      await tester.tap(find.text('ログアウトを再試行')); await drain(tester);
      expect(w.auth.logoutQuarantine.state,AppLogoutQuarantineState.clear);
      expect(w.calls,hasLength(requests));
      expect(find.text('fresh root'),findsOneWidget);
    } finally { await cleanup(tester,w); }
  });
}
