import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/login_method_enrollment_card.dart';
import 'package:sk_works/features/auth/login_method_enrollment_repository.dart';

class Source implements LoginMethodEnrollmentSource {
  bool phoneAvailable = false;
  int loads = 0, passwords = 0, phoneRequests = 0, confirmations = 0, cancellations = 0;
  bool fail = false;
  @override
  Future<LoginMethodEnrollmentState> load() async {
    loads++;
    return LoginMethodEnrollmentState(email: 'existing@example.invalid', phone: '',
      emailConfirmed: true, phoneConfirmed: false, emailAvailable: true,
      phoneAvailable: phoneAvailable);
  }
  @override
  Future<void> setPrimaryPassword(String value, {String? nonce}) async {
    if (fail) throw StateError('保存結果を確認できません。');
    passwords++;
  }
  @override Future<void> requestPrimaryPasswordCode() async {}
  @override Future<void> requestPhone(String value) async { phoneRequests++; }
  @override Future<void> confirmPhone(String value) async { confirmations++; }
  @override Future<void> requestEmail(String value) async {}
  @override void cancelPhone() { cancellations++; }
  @override void dispose() {}
}

void main() {
  Future<void> show(WidgetTester tester, Source source) async {
    await tester.binding.setSurfaceSize(const Size(700, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: LoginMethodEnrollmentCard(source: source)))));
    await tester.pumpAndSettle();
  }

  testWidgets('provider OFF disables phone sending while primary password remains available', (t) async {
    final source = Source();
    await show(t, source);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '電話番号を登録')).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '第一パスワードを設定・変更')).onPressed, isNotNull);
    expect(source.phoneRequests, 0);
  });

  testWidgets('password cancellation never saves; matching confirmation saves and reloads', (t) async {
    final source = Source();
    await show(t, source);
    await t.tap(find.text('第一パスワードを設定・変更'));
    await t.pumpAndSettle();
    await t.tap(find.text('キャンセル'));
    await t.pumpAndSettle();
    expect(source.passwords, 0);
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
    expect(source.loads, 2);
    expect(find.textContaining('第二パスワードは変更していません。'), findsOneWidget);
  });

  testWidgets('failed password save never displays success', (t) async {
    final source = Source()..fail = true;
    await show(t, source);
    await t.tap(find.text('第一パスワードを設定・変更'));
    await t.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await t.enterText(find.byType(TextField).at(i), 'New-primary-password');
    }
    await t.pump(); await t.tap(find.text('保存')); await t.pumpAndSettle();
    expect(source.passwords, 0);
    expect(find.text('保存結果を確認できません。'), findsOneWidget);
    expect(find.textContaining('第一パスワードの保存と同じ'), findsNothing);
  });

  testWidgets('phone SMS request remains unconfirmed until code verification', (t) async {
    final source = Source()..phoneAvailable = true;
    await show(t, source);
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
    expect(find.text('電話番号の所有確認と登録を確認しました。'), findsOneWidget);
  });
}
