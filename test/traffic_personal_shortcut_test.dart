import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sk_works/features/traffic/traffic_personal_shortcut.dart';
import 'package:sk_works/features/traffic/traffic_shortcut_store.dart';

class _MemoryStore implements TrafficShortcutStore {
  final values = <TrafficShortcutScope, TrafficShortcut>{};
  Completer<TrafficShortcut?>? pending;
  bool failSave = false;
  Completer<void>? pendingSave;
  @override
  Future<TrafficShortcut?> load(TrafficShortcutScope scope) async {
    if (pending != null) return await pending!.future;
    return values[scope];
  }
  @override
  Future<void> save(TrafficShortcutScope scope, TrafficShortcut? shortcut) async {
    if (pendingSave != null) await pendingSave!.future;
    if (failSave) throw StateError('fixture');
    if (shortcut == null) { values.remove(scope); } else { values[scope] = shortcut; }
  }
}
void main() {
  const alice = TrafficShortcutScope(actorId: 'alice', companyId: 'company');
  const bob = TrafficShortcutScope(actorId: 'bob', companyId: 'company');
  const otherCompany = TrafficShortcutScope(actorId: 'alice', companyId: 'other');
  Future<void> pump(WidgetTester tester, _MemoryStore store, {
    TrafficShortcutScope? scope = alice, bool available = true, Future<bool> Function(Uri)? open,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: SizedBox(width: 58, child: TrafficPersonalShortcut(scope: scope, store: store,
        canOpen: (_) async => available, open: open ?? (_) async => true)),
    ))));
    await tester.pump();
  }
  test('local persisted shortcut is separated by actor and company', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceTrafficShortcutStore();
    await store.save(alice, const TrafficShortcut.googleMaps());
    expect((await store.load(alice))!.uri.toString(), 'comgooglemaps://');
    expect(await store.load(bob), isNull);
    expect(await store.load(otherCompany), isNull);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(bob.storageKey, '{malformed');
    expect(await store.load(bob), isNull);
    expect(preferences.getString(bob.storageKey), '{malformed');
    await store.save(alice, TrafficShortcut.web('時刻表', 'https://example.com/timetable'));
    expect((await store.load(alice))!.label, '時刻表');
    await store.save(alice, null);
    expect(await store.load(alice), isNull);
  });
  test('web URL cannot introduce arbitrary app schemes or embedded credentials', () {
    for (final url in ['javascript:alert(1)', 'comgooglemaps://', 'http://example.com', 'https://name:pass@example.com', 'https://example.com/a b', 'https://']) {
      expect(TrafficShortcut.web('リンク', url), isNull);
    }
    expect(TrafficShortcut.web('リンク', 'https://example.com/?page=2')!.uri.host, 'example.com');
    expect(TrafficShortcut.fromJson(jsonDecode('{"version":1,"kind":"unknown"}')), isNull);
  });
  testWidgets('add shows only detected supported app and persists one choice', (tester) async {
    final store = _MemoryStore();
    await pump(tester, store);
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    expect(find.text('Googleマップ'), findsOneWidget);
    expect(find.textContaining('マスター'), findsNothing);
    await tester.tap(find.text('Googleマップ')); await tester.pumpAndSettle();
    expect(store.values[alice]!.kind, TrafficShortcutKind.googleMaps);
    await pump(tester, store, scope: bob, available: false);
    expect(find.text('追加'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    expect(find.text('Googleマップ'), findsNothing);
    expect(find.text('Webサイトを登録'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('web validates, saves, opens, edits and removes locally', (tester) async {
    final store = _MemoryStore(); final opened = <Uri>[];
    await pump(tester, store, available: false, open: (uri) async { opened.add(uri); return true; });
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Webサイトを登録')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('traffic-web-name')), '時刻表');
    await tester.enterText(find.byKey(const ValueKey('traffic-web-url')), 'http://example.com');
    await tester.tap(find.text('登録')); await tester.pumpAndSettle();
    expect(find.text('https://で始まるURLを入力してください。'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('traffic-web-url')), 'https://example.com');
    await tester.tap(find.text('登録')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    expect(opened.single.host, 'example.com');
    await tester.longPress(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    await tester.tap(find.text('登録を解除')); await tester.pumpAndSettle();
    expect(store.values, isEmpty);
    expect(find.text('追加'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('app removed after registration gives editable error', (tester) async {
    final store = _MemoryStore()..values[alice] = const TrafficShortcut.googleMaps();
    var calls = 0;
    await pump(tester, store, available: false, open: (_) async { calls++; return true; });
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('登録した項目を開けませんでした。編集して選び直してください。'), findsOneWidget);
    await tester.tap(find.text('編集')); await tester.pumpAndSettle();
    expect(find.text('登録を解除'), findsOneWidget);
  });
  testWidgets('scope change rejects delayed old load and closes old editor', (tester) async {
    final store = _MemoryStore()..pending = Completer<TrafficShortcut?>();
    await pump(tester, store);
    final old = store.pending!; store.pending = null;
    await pump(tester, store, scope: bob);
    old.complete(const TrafficShortcut.googleMaps()); await tester.pumpAndSettle();
    expect(find.text('Googleマップ'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Webサイトを登録')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('traffic-web-name')), '個人のリンク');
    await pump(tester, store, scope: alice); await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('traffic-web-name')), findsNothing);
    expect(find.text('個人のリンク'), findsNothing);
    expect(store.values, isEmpty);
  });
  testWidgets('scope switch ignores a delayed old-account launch failure', (tester) async {
    final store = _MemoryStore()..values[alice] = const TrafficShortcut.googleMaps();
    final pending = Completer<bool>();
    await pump(tester, store, open: (_) => pending.future);
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pump();
    await pump(tester, store, scope: bob);
    pending.complete(false); await tester.pumpAndSettle();
    expect(find.text('追加'), findsOneWidget);
    expect(find.text('登録した項目を開けませんでした。編集して選び直してください。'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('save started by old account cannot replace new-account shortcut', (tester) async {
    final store = _MemoryStore();
    store.values[bob] = TrafficShortcut.web('別アカウント', 'https://example.com/bob')!;
    store.pendingSave = Completer<void>();
    await pump(tester, store);
    await tester.tap(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    await tester.tap(find.text('Googleマップ')); await tester.pumpAndSettle();
    await pump(tester, store, scope: bob);
    store.pendingSave!.complete(); await tester.pumpAndSettle();
    expect(store.values[alice]!.kind, TrafficShortcutKind.googleMaps);
    expect(store.values[bob]!.label, '別アカウント');
    expect(find.text('別アカウント'), findsOneWidget);
    expect(find.text('Googleマップ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save preserves prior choice; absent scope cannot register', (tester) async {
    final store = _MemoryStore();
    store.values[alice] = const TrafficShortcut.googleMaps();
    store.failSave = true;
    await pump(tester, store);
    await tester.longPress(find.byKey(const ValueKey('traffic-personal-shortcut'))); await tester.pumpAndSettle();
    await tester.tap(find.text('登録を解除')); await tester.pumpAndSettle();
    expect(store.values[alice]!.kind, TrafficShortcutKind.googleMaps);
    expect(find.text('追加した項目を保存できませんでした。'), findsOneWidget);
    await pump(tester, store, scope: null);
    final button = tester.widget<TextButton>(find.byKey(const ValueKey('traffic-personal-shortcut')));
    expect(button.onPressed, isNull);
  });
}
