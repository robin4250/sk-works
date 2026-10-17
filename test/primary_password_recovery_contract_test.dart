import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retired primary SMS reset has no repository entry point; initial registration remains', () {
    final source = File('lib/features/auth/secure_onboarding_repository.dart').readAsStringSync();
    expect(source, isNot(contains('requestPasswordResetSms')));
    expect(source, isNot(contains('verifyPasswordResetSms')));
    expect(source, isNot(contains('signInWithOtp(')));
    expect(source, contains('Future<bool> registerAdmin('));
    expect(source, contains('Future<void> verifySmsCode('));
    expect(source, contains('Future<void> setEmployeePrimaryPassword('));
    expect(source, contains('UserAttributes(password: password)'));
  });
}

