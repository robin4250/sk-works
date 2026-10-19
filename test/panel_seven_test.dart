import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/panel_seven_page.dart';
import 'package:sk_works/features/auth/panel_seven_repository.dart';

PanelSevenSnapshot snapshot() => const PanelSevenSnapshot(
  actorId: 'a', providers: ['google'], email: 'owner@example.test',
  phone: null, emailConfirmed: true, phoneConfirmed: false,
  sessionMethods: ['oauth'], secondaryConfigured: true,
  accessToken: 'synthetic',
);

class FakeRepository implements PanelSevenSource {
  bool current = true;
  int loads = 0;
  Future<PanelSevenSnapshot>? nextLoad;
  final events = StreamController<AuthState>.broadcast();
  @override
  Stream<AuthState> get changes => events.stream;
  @override
  bool isCurrent(PanelSevenSnapshot snapshot) => current;
  @override
  Future<PanelSevenSnapshot> load() async {
    loads++;
    final pending = nextLoad;
    nextLoad = null;
    if (pending != null) return pending;
    if (!current) throw StateError('changed');
    return snapshot();
  }
}

void main() {
  testWidgets('shows linked Google separately from actual session method and passwords',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('外部アカウント認証（提供元は特定できません）'), findsOneWidget);
    expect(find.textContaining('設定状況は確認できません'), findsOneWidget);
    expect(find.text('第一パスワード（ログイン用）'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account-secondary-password')), 100);
    expect(find.text('設定済み'), findsOneWidget);
    expect(find.text('第二パスワード（重要情報用）'), findsOneWidget);
    expect(find.text('Master 緊急復旧設定'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('actor change removes old personal details and shows retry',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    repository.current = false;
    repository.events.add(const AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();
    expect(find.text('owner@example.test'), findsNothing);
    expect(find.text('本人のアカウント情報を確認できませんでした。'), findsOneWidget);
  });

  testWidgets('help explains local biometrics without claiming server MFA',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('使い方'));
    await tester.pumpAndSettle();
    expect(find.text('アカウント設定について'), findsOneWidget);
    expect(find.textContaining('端末内の本人確認'), findsWidgets);
    expect(find.textContaining('マスター管理の権限や専用パスワードの設定状況を示しません'), findsOneWidget);
  });
  testWidgets('background events and late pending reads cannot restore personal data',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    final pending = Completer<PanelSevenSnapshot>();
    repository.nextLoad = pending.future;
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    expect(repository.loads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.events.add(const AuthState(AuthChangeEvent.tokenRefreshed, null));
    pending.complete(snapshot());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(repository.loads, 1);
    expect(find.text('Google'), findsNothing);
    expect(find.textContaining('owner@example.test'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.loads, 2);
    expect(find.text('Google'), findsOneWidget);
  });

}

