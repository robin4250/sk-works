import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login screen exposes a visible initial registration button', () {
    final auth = File(
      'lib/features/auth/secure_onboarding_pages.dart',
    ).readAsStringSync();

    expect(auth, contains("OutlinedButton.icon("));
    expect(auth, contains("'初回登録'"));
    expect(auth, contains("_registerMode = !_registerMode"));
    expect(
      auth.indexOf("'初回登録'"),
      lessThan(auth.indexOf("'従業員登録QRでログイン'")),
      reason: '初回登録はQRログインより上に表示する',
    );
  });

  test('employee onboarding uses language controller and contextual help', () {
    final pages =
        File('lib/features/auth/employee_onboarding_pages.dart').readAsStringSync();
    final scanner =
        File('lib/features/auth/employee_invite_scanner_page.dart').readAsStringSync();

    expect(pages, contains("import '../../international/language_controller.dart';"));
    expect(pages, contains('Icons.help_outline'));
    expect(pages, contains("SkoLanguageController.tr('本パスワード設定')"));
    expect(pages, contains("SkoLanguageController.tr('本人情報登録')"));
    expect(pages, contains("SkoLanguageController.tr('本登録承認待ち')"));
    expect(pages, contains("SkoLanguageController.tr('本登録を申請')"));
    expect(scanner, contains('Icons.help_outline'));
    expect(scanner, contains("SkoLanguageController.tr('従業員登録QRを読み取る')"));
  });

  test('English language pack covers employee onboarding flow', () {
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();

    for (final key in [
      '本パスワード設定',
      '本人情報登録',
      '本登録を申請',
      '本登録承認待ち',
      '承認状況を更新',
      'この従業員登録は期限切れです',
      '従業員登録QRを読み取る',
      'この画面の使い方',
    ]) {
      expect(english, contains("'$key':"));
    }
  });

  test('employee onboarding keeps existing secure workflow links', () {
    final gate = File('lib/features/auth/auth_gate.dart').readAsStringSync();
    final pages =
        File('lib/features/auth/employee_onboarding_pages.dart').readAsStringSync();

    expect(gate, contains('_GateStatus.employeePassword'));
    expect(gate, contains('_GateStatus.employeeProfile'));
    expect(gate, contains('_GateStatus.employeeApprovalPending'));
    expect(pages, contains('setEmployeePrimaryPassword'));
    expect(pages, contains('submitProfile'));
  });
}
