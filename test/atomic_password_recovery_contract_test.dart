import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logged-out primary page cannot update password or send reset OTP', () {
    final all = File('lib/features/auth/secure_onboarding_pages.dart').readAsStringSync();
    final page = all.substring(0, all.indexOf('class SecondaryPasswordSetupPage'));
    expect(page, contains('本パスワードを忘れた方'));
    expect(page, contains('復旧方法を確認できません'));
    expect(page, isNot(contains('updatePrimaryPassword(')));
    expect(page, isNot(contains('requestPasswordResetSms(')));
    expect(page, isNot(contains('verifyPasswordResetSms(')));
    expect(page, isNot(contains('authenticate(')));
    expect(page, contains('従業員登録QRでログイン'));
  });
}
