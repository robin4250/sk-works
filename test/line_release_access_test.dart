import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/chat/chat_cloud_repository.dart';
import 'package:sk_works/features/chat/line_release_access.dart';
import 'package:sk_works/features/chat/line_talk_hub_page.dart';

class _CachedBody extends StatefulWidget {
  const _CachedBody(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_CachedBody> createState() => _CachedBodyState();
}
class _CachedBodyState extends State<_CachedBody> {
  final draft = TextEditingController(text: 'private LINE draft');
  @override
  void dispose() { draft.dispose(); widget.onDispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(body: TextField(controller: draft));
}

void main() {
  testWidgets('a direct LINE entry is fail closed without a backend', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LineTalkHubPage()));
    expect(find.text('LINEトークは現在利用できません。'), findsOneWidget);
    expect(find.text('参加済みグループ一覧'), findsNothing);
  });

  testWidgets('revocation disposes cached text and requires fresh child construction', (tester) async {
    final actors = StreamController<String?>.broadcast(sync: true);
    var actor = 'a', allowed = true, disposed = 0;
    final access = LineReleaseAccess(read: () async => allowed,
      currentActor: () => actor, actorChanges: actors.stream, observeLifecycle: false);
    await tester.pumpWidget(LineReleaseScope(access: access,
      child: MaterialApp(home: LineReleaseBoundary(builder: (_) => _CachedBody(() => disposed++)))));
    await tester.pumpAndSettle();
    expect(find.text('private LINE draft'), findsOneWidget);
    allowed = false;
    await access.refresh(); await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing); expect(disposed, 1);
    allowed = true;
    await access.refresh(); await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); access.dispose(); await actors.close();
  });

  testWidgets('actor A to B to A cannot revive an old in-flight approval', (tester) async {
    final actors = StreamController<String?>.broadcast(sync: true);
    String? actor = 'a';
    final pending = <Completer<bool>>[];
    final access = LineReleaseAccess(read: () { final c = Completer<bool>(); pending.add(c); return c.future; },
      currentActor: () => actor, actorChanges: actors.stream, observeLifecycle: false);
    expect(access.available, false);
    actor = 'b'; actors.add(actor);
    actor = 'a'; actors.add(actor);
    pending.first.complete(true); await tester.pump();
    expect(access.available, false);
    pending.last.complete(true); await tester.pump();
    expect(access.available, true);
    actor = null; actors.add(null); expect(access.available, false);
    access.dispose(); await actors.close();
    for (final c in pending) { if (!c.isCompleted) c.complete(false); }
  });

  testWidgets('read errors revoke existing permission and purge child', (tester) async {
    var fail = false;
    final access = LineReleaseAccess(read: () async { if (fail) throw StateError('offline'); return true; },
      currentActor: () => 'a', actorChanges: const Stream.empty(), observeLifecycle: false);
    await tester.pumpWidget(LineReleaseScope(access: access,
      child: MaterialApp(home: LineReleaseBoundary(builder: (_) => const Text('secret received body')))));
    await tester.pumpAndSettle(); expect(find.text('secret received body'), findsOneWidget);
    fail = true; await access.refresh(); await tester.pumpAndSettle();
    expect(find.text('secret received body'), findsNothing);
    await tester.pumpWidget(const SizedBox()); access.dispose();
  });

  testWidgets('background return hides old text until fresh server verification', (tester) async {
    var pending = Completer<bool>()..complete(true);
    final access = LineReleaseAccess(read: () => pending.future,
      currentActor: () => 'a', actorChanges: const Stream.empty(), observeLifecycle: false);
    await tester.pumpWidget(LineReleaseScope(access: access,
      child: MaterialApp(home: LineReleaseBoundary(builder: (_) => const Text('LINE body')))));
    await tester.pumpAndSettle(); expect(find.text('LINE body'), findsOneWidget);
    access.didChangeAppLifecycleState(AppLifecycleState.paused);
    pending = Completer<bool>();
    access.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(); expect(find.text('LINE body'), findsNothing);
    pending.complete(false); await tester.pumpAndSettle();
    expect(find.text('LINE body', skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox()); access.dispose();
  });

  test('unavailable LINE removes received bodies while preserving ordinary SKO', () {
    final rows = <Map<String, dynamic>>[
      {'id':'s', 'body':'SKO text', 'origin':'sk_works'},
      {'id':'l', 'body':'LINE text', 'origin':'line'},
    ];
    expect(filterLineReleaseMessages(rows, false).map((r) => r['id']), ['s']);
    expect(filterLineReleaseMessages(rows, true).length, 2);
  });
}
