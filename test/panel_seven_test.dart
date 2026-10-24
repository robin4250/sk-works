import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sk_works/features/auth/panel_seven_page.dart';
import 'package:sk_works/features/auth/panel_seven_repository.dart';
import 'package:sk_works/features/auth/login_method_enrollment_card.dart';

PanelSevenSnapshot snapshot({bool? primaryConfigured}) => PanelSevenSnapshot(
  actorId: 'a', providers: const ['google'], email: 'owner@example.test',
  phone: null, emailConfirmed: true, phoneConfirmed: false,
  sessionMethods: const ['oauth'], secondaryConfigured: true, primaryConfigured: primaryConfigured,
  accessToken: 'synthetic',
);

class FakeRepository implements PanelSevenSource {
  bool current = true;
  int loads = 0;
  PanelSevenSnapshot? value;
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
    return value ?? snapshot();
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
    expect(find.textContaining('登録の有無は取得できません'), findsOneWidget);
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

  testWidgets('only password receipt changes status and session change clears it',
      (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(
        repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(LoginMethodEnrollmentCard), 200);
    final card = tester.widget<LoginMethodEnrollmentCard>(
        find.byType(LoginMethodEnrollmentCard));
    // The generic phone/email refresh is not password-save evidence.
    card.onChanged!();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('account-primary-password')), -200);
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました'), findsNothing);
    card.onPrimaryPasswordSaved!();
    await tester.pumpAndSettle();
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました'), findsOneWidget);
    repository.current = false;
    repository.events.add(const AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();
    repository.current = true;
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました'), findsNothing);
    expect(find.textContaining('登録の有無は取得できません'), findsOneWidget);
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

  testWidgets('confirmed Google email has collapsed next-login guidance without pretending password is set', (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(repository: repository)));
    await tester.pumpAndSettle();
    final guide = find.byKey(const ValueKey('account-email-login-guide'));
    await tester.scrollUntilVisible(guide, 100);
    expect(tester.widget<ExpansionTile>(guide).initiallyExpanded, false);
    await tester.tap(find.text('メールでログインするには')); await tester.pumpAndSettle();
    expect(find.textContaining('現在のGoogleログインをログアウトする必要はありません。'), findsOneWidget);
    expect(find.textContaining('この確認済みメールと保存した第一パスワードを使います。'), findsOneWidget);
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました。'), findsNothing);
    expect(repository.loads, 1);
  });

  testWidgets('unconfirmed email never shows confirmed-email login guidance', (tester) async {
    final repository = FakeRepository()..value = const PanelSevenSnapshot(
      actorId: 'a', providers: ['google'], email: 'owner@example.test', phone: null,
      emailConfirmed: false, phoneConfirmed: false, sessionMethods: ['oauth'],
      secondaryConfigured: true, accessToken: 'synthetic');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(repository: repository)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-email-login-guide')), findsNothing);
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました。'), findsNothing);
    expect(repository.loads, 1);
  });

  for (final configured in <bool?>[true, false, null]) {
    testWidgets('primary self status $configured is distinct from local save receipt', (tester) async {
      final repository = FakeRepository()..value = snapshot(primaryConfigured: configured);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.events.close();
      });
      await tester.pumpWidget(MaterialApp(home: PanelSevenPage(repository: repository)));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('account-primary-password'));
      await tester.scrollUntilVisible(row, 100);
      final text = tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
          .map((w) => w.data ?? '').join(' ');
      if (configured == true) {
        expect(text, contains('設定済みです。'));
        expect(text, isNot(contains('未設定です。')));
        expect(text, isNot(contains('登録の有無は取得できません')));
      } else if (configured == false) {
        expect(text, contains('未設定です。'));
        expect(text, isNot(contains('設定済みです。')));
        expect(text, isNot(contains('登録の有無は取得できません')));
      } else {
        expect(text, contains('登録の有無は取得できません'));
        expect(text, isNot(contains('未設定です。')));
        expect(text, isNot(contains('設定済みです。')));
      }
      expect(text, isNot(contains('この画面で第一パスワードの保存を確認しました')));
    });
  }

  testWidgets('new explicit empty status supersedes older local save receipt', (tester) async {
    final repository = FakeRepository();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.events.close();
    });
    await tester.pumpWidget(MaterialApp(home: PanelSevenPage(repository: repository)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(LoginMethodEnrollmentCard), 200);
    final card = tester.widget<LoginMethodEnrollmentCard>(find.byType(LoginMethodEnrollmentCard));
    card.onPrimaryPasswordSaved!(); await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('account-primary-password')), -200);
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました'), findsOneWidget);
    repository.value = snapshot(primaryConfigured: false);
    card.onChanged!(); await tester.pumpAndSettle();
    expect(find.textContaining('未設定です。'), findsOneWidget);
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました'), findsNothing);
    repository.value = snapshot();
    card.onChanged!(); await tester.pumpAndSettle();
    expect(find.textContaining('登録の有無は取得できません'), findsOneWidget);
    expect(find.textContaining('この画面で第一パスワードの保存を確認しました'), findsNothing);
  });

}
