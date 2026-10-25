import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/login_method_enrollment_card.dart';
import 'package:sk_works/features/auth/login_method_enrollment_repository.dart';

class Source implements LoginMethodEnrollmentSource {
  String email = 'existing@example.invalid';
  bool phoneAvailable = false, phoneRegistrationReady = true;
  int loads = 0, passwords = 0, phoneRequests = 0, confirmations = 0, cancellations = 0;
  bool fail = false, pendingPhone = false, failLoad = false, failLoadAfterPassword = false;
  String phone = '';
  bool phoneConfirmed = false;
  Future<LoginMethodEnrollmentState>? nextLoad;
  Object? readFailure;
  @override
  Future<LoginMethodEnrollmentState> load() async {
    loads++;
    final pending = nextLoad;
    nextLoad = null;
    if (pending != null) return await pending;
    if (readFailure != null) throw readFailure!;
    if (failLoad) throw StateError('synthetic settings unavailable');
    return LoginMethodEnrollmentState(email: email, phone: phone,
      emailConfirmed: true, phoneConfirmed: phoneConfirmed, emailAvailable: true,
      phoneAvailable: phoneAvailable, phoneRegistrationReady: phoneRegistrationReady,
      phoneConfirmationPending: pendingPhone);
  }
  @override
  Future<void> setPrimaryPassword(String value, {String? nonce}) async {
    if (fail) throw StateError('保存結果を確認できません。');
    passwords++;
    if (failLoadAfterPassword) failLoad = true;
  }
  @override Future<void> requestPrimaryPasswordCode() async {}
  @override Future<void> requestPhone(String value) async { phoneRequests++; pendingPhone = true; }
  @override Future<void> confirmPhone(String value) async { confirmations++; pendingPhone = false; phone = '819012345678'; phoneConfirmed = true; }
  @override Future<void> requestEmail(String value) async {}
  @override void cancelPhone() { cancellations++; pendingPhone = false; }
  @override void dispose() {}
}

void main() {
  Future<void> show(WidgetTester tester, Source source,
      {VoidCallback? onPrimaryPasswordSaved}) async {
    await tester.binding.setSurfaceSize(const Size(700, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: LoginMethodEnrollmentCard(source: source,
        onPrimaryPasswordSaved: onPrimaryPasswordSaved)))));
    await tester.pumpAndSettle();
  }

  testWidgets('provider OFF disables phone sending while primary password remains available', (t) async {
    final source = Source();
    await show(t, source);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '電話番号登録（準備中）')).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '第一パスワードを設定・変更')).onPressed, isNotNull);
    expect(source.phoneRequests, 0);
  });

  testWidgets('password cancellation never saves; matching confirmation saves and reloads', (t) async {
    final source = Source();
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    await t.tap(find.text('第一パスワードを設定・変更'));
    await t.pumpAndSettle();
    await t.tap(find.text('キャンセル'));
    await t.pumpAndSettle();
    expect(source.passwords, 0);
    expect(receipts, 0);
    await t.tap(find.text('第一パスワードを設定・変更'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'New-primary-password');
    await t.enterText(find.byType(TextField).at(1), 'Mismatch-password');
    await t.pump();
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, '保存')).onPressed, isNull);
    await t.enterText(find.byType(TextField).at(1), 'New-primary-password');
    await t.pump();
    await t.tap(find.text('保存'));
    await t.pumpAndSettle();
    expect(source.passwords, 1);
    expect(receipts, 1);
    expect(source.loads, 2);
    expect(find.textContaining('第二パスワードは変更していません。'), findsOneWidget);
  });

  testWidgets('failed password save never displays success', (t) async {
    final source = Source()..fail = true;
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    await t.tap(find.text('第一パスワードを設定・変更'));
    await t.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await t.enterText(find.byType(TextField).at(i), 'New-primary-password');
    }
    await t.pump(); await t.tap(find.text('保存')); await t.pumpAndSettle();
    expect(source.passwords, 0);
    expect(receipts, 0);
    expect(find.text('保存結果を確認できません。'), findsOneWidget);
    expect(find.textContaining('第一パスワードの保存と同じ'), findsNothing);
  });

  testWidgets('advertised phone provider cannot enable unreleased SMS registration', (t) async {
    final source=Source()..phoneAvailable=true..phoneRegistrationReady=false;
    await show(t,source);
    final button=find.widgetWithText(OutlinedButton,'電話番号登録（準備中）');
    expect(t.widget<OutlinedButton>(button).onPressed,isNull);
    expect(find.textContaining('電話番号の新規登録は準備中'),findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'第一パスワードを設定・変更')).onPressed,isNotNull);
    expect(source.phoneRequests,0);expect(source.confirmations,0);
    expect(find.text('電話番号は登録確認済みです。'),findsNothing);
  });
  testWidgets('paused registration preserves previously verified phone evidence', (t) async {
    final source=Source()..phoneAvailable=true..phoneRegistrationReady=false
      ..phone='819012345678'..phoneConfirmed=true;
    await show(t,source);
    expect(find.text('電話番号は登録確認済みです。'),findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'電話番号登録（準備中）')).onPressed,isNull);
    expect(source.phoneRequests,0);expect(source.confirmations,0);
  });
  testWidgets('phone SMS request remains unconfirmed until code verification', (t) async {
    final source = Source()..phoneAvailable = true;
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    await t.tap(find.text('電話番号を登録')); await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '09012345678'); await t.pump();
    await t.tap(find.text('確認へ')); await t.pumpAndSettle();
    expect(source.phoneRequests, 1);
    expect(source.confirmations, 0);
    expect(find.textContaining('まだ電話番号の登録は完了していません。'), findsOneWidget);
    await t.tap(find.text('SMSコードを入力')); await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '123456'); await t.pump();
    await t.tap(find.text('確認へ')); await t.pumpAndSettle();
    expect(source.confirmations, 1);
    expect(receipts, 0);
    expect(find.text('電話番号の所有確認と登録を確認しました。'), findsOneWidget);
  });
  testWidgets('email enrollment never emits a password-save receipt', (t) async {
    final source = Source()..email = '';
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    await t.tap(find.text('メールアドレスを登録')); await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'new@example.invalid');
    await t.pump(); await t.tap(find.text('確認へ')); await t.pumpAndSettle();
    expect(find.textContaining('確認メールを送信しました。'), findsOneWidget);
    expect(receipts, 0);
  });
  testWidgets('page-owned pending SMS survives card teardown and rebuild', (t) async {
    final source = Source()..phoneAvailable = true;
    await show(t, source);
    await t.tap(find.text('電話番号を登録')); await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '09012345678'); await t.pump();
    await t.tap(find.text('確認へ')); await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox.shrink()); await t.pumpAndSettle();
    expect(source.cancellations, 0);
    await show(t, source);
    expect(find.text('SMSコードを入力'), findsOneWidget);
    expect(source.phoneRequests, 1);
  });

  testWidgets('unregistered phone and disabled provider are separate facts', (t) async {
    final source = Source();
    await show(t, source);
    expect(find.text('電話番号は未登録です。'), findsOneWidget);
    expect(find.textContaining('電話番号の新規登録は準備中'), findsOneWidget);
    expect(find.text('電話番号は登録確認済みです。'), findsNothing);
    await t.tap(find.text('？ 登録状況の見方')); await t.pumpAndSettle();
    expect(find.textContaining('電話番号の登録状況と、SMSを送れる提供状態は別です。'), findsOneWidget);
    expect(source.phoneRequests, 0);
  });

  testWidgets('unconfirmed phone is not reported as absent or registered', (t) async {
    final source = Source()..phone = '819012345678'..phoneAvailable = true;
    await show(t, source);
    expect(find.text('電話番号の登録確認は未完了です。'), findsOneWidget);
    expect(find.text('電話番号は未登録です。'), findsNothing);
    expect(find.text('電話番号は登録確認済みです。'), findsNothing);
    expect(source.phoneRequests, 0);
  });

  testWidgets('settings failure removes stale registration and provider actions then recovers', (t) async {
    final source = Source()..phoneAvailable = true;
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    expect(find.text('電話番号は未登録です。'), findsOneWidget);
    source.failLoad = true;
    await t.tap(find.text('登録方法を再読み込み')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsOneWidget);
    expect(find.text('電話番号は未登録です。'), findsNothing);
    expect(find.textContaining('電話番号の新規登録は準備中'), findsNothing);
    expect(find.text('電話番号を登録'), findsNothing);
    expect(find.text('第一パスワードを設定・変更'), findsNothing);
    source.failLoad = false; source.phoneAvailable = false;
    await t.tap(find.text('登録方法を再読み込み')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsNothing);
    expect(find.text('電話番号は未登録です。'), findsOneWidget);
    expect(find.textContaining('電話番号の新規登録は準備中'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '第一パスワードを設定・変更')).onPressed, isNotNull);
    expect(receipts, 0); expect(source.phoneRequests, 0);
  });

  testWidgets('latest reload wins and no stale actions appear while checking', (t) async {
    final source = Source()..phoneAvailable = true;
    await show(t, source);
    final older = Completer<LoginMethodEnrollmentState>();
    source.nextLoad = older.future;
    await t.tap(find.text('登録方法を再読み込み')); await t.pump();
    expect(find.text('電話番号を登録'), findsNothing);
    source.phoneAvailable = false;
    await t.tap(find.text('登録方法を再読み込み')); await t.pumpAndSettle();
    older.complete(const LoginMethodEnrollmentState(email: 'old@example.invalid', phone: '',
      emailConfirmed: true, phoneConfirmed: false, emailAvailable: true, phoneAvailable: true));
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '電話番号登録（準備中）')).onPressed, isNull);
    expect(find.textContaining('電話番号の新規登録は準備中'), findsOneWidget);
    expect(source.phoneRequests, 0);
  });

  testWidgets('initial unavailable settings do not imply disabled provider or missing phone', (t) async {
    final source = Source()..failLoad = true;
    await show(t, source);
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsOneWidget);
    expect(find.textContaining('電話番号の新規登録は準備中'), findsNothing);
    expect(find.text('電話番号は未登録です。'), findsNothing);
    expect(find.text('電話番号は登録確認済みです。'), findsNothing);
    expect(source.phoneRequests, 0);
  });

  testWidgets('verified password receipt survives a subsequent settings read failure', (t) async {
    final source = Source()..failLoadAfterPassword = true;
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    await t.tap(find.text('第一パスワードを設定・変更')); await t.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await t.enterText(find.byType(TextField).at(i), 'New-primary-password');
    }
    await t.pump(); await t.tap(find.text('保存')); await t.pumpAndSettle();
    expect(source.passwords, 1); expect(receipts, 1);
    expect(find.textContaining('第一パスワードの保存と同じアカウントを確認しました。'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsOneWidget);
    expect(find.text('電話番号を登録'), findsNothing);
  });

  testWidgets('fixed read stages are visible without stale actions or false registration', (t) async {
    final source = Source();
    var receipts = 0;
    await show(t, source, onPrimaryPasswordSaved: () => receipts++);
    for (final stage in LoginEnrollmentReadStage.values) {
      source.readFailure = LoginEnrollmentReadFailure(stage);
      await t.tap(find.text('登録方法を再読み込み')); await t.pumpAndSettle();
      expect(find.text(LoginEnrollmentReadFailure(stage).message), findsOneWidget);
      expect(find.text('電話番号を登録'), findsNothing);
      expect(find.text('電話番号は未登録です。'), findsNothing);
      expect(find.text('電話番号は登録確認済みです。'), findsNothing);
      expect(find.textContaining('電話番号の新規登録は準備中'), findsNothing);
      expect(find.text('第一パスワードを設定・変更'), findsNothing);
    }
    source.readFailure = null;
    await t.tap(find.text('登録方法を再読み込み')); await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsNothing);
    expect(find.text('電話番号は未登録です。'), findsOneWidget);
    expect(find.textContaining('電話番号の新規登録は準備中'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '第一パスワードを設定・変更')).onPressed, isNotNull);
    expect(source.phoneRequests, 0); expect(source.passwords, 0); expect(receipts, 0);
  });

  testWidgets('unknown read error never displays upstream body identifiers or token', (t) async {
    final source = Source()..readFailure = StateError('PRIVATE_BODY actor=synthetic-user token=synthetic-bearer');
    await show(t, source);
    expect(find.text('登録状況と提供状態を確認できませんでした。再読み込みしてください。'), findsOneWidget);
    final text = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' ');
    for (final secret in ['PRIVATE_BODY', 'synthetic-user', 'synthetic-bearer']) {
      expect(text, isNot(contains(secret)));
    }
    expect(find.text('電話番号は未登録です。'), findsNothing);
    expect(source.phoneRequests, 0); expect(source.passwords, 0);
  });

  testWidgets('late failed read cannot replace a newer successful provider state', (t) async {
    final source = Source()..phoneAvailable = true;
    await show(t, source);
    final older = Completer<LoginMethodEnrollmentState>(); source.nextLoad = older.future;
    await t.tap(find.text('登録方法を再読み込み')); await t.pump();
    expect(find.text('電話番号を登録'), findsNothing);
    source.phoneAvailable = false;
    await t.tap(find.text('登録方法を再読み込み')); await t.pumpAndSettle();
    older.completeError(const LoginEnrollmentReadFailure(LoginEnrollmentReadStage.verifiedUser));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsNothing);
    expect(find.text('電話番号は未登録です。'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '電話番号登録（準備中）')).onPressed, isNull);
    expect(source.phoneRequests, 0); expect(t.takeException(), isNull);
  });

  testWidgets('late failure after card teardown cannot surface stale diagnostic', (t) async {
    final source = Source();
    await show(t, source);
    final pending = Completer<LoginMethodEnrollmentState>(); source.nextLoad = pending.future;
    await t.tap(find.text('登録方法を再読み込み')); await t.pump();
    await t.pumpWidget(const SizedBox.shrink());
    pending.completeError(const LoginEnrollmentReadFailure(LoginEnrollmentReadStage.providerSettings));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-enrollment-load-error')), findsNothing);
    expect(t.takeException(), isNull); expect(source.phoneRequests, 0);
  });

}
