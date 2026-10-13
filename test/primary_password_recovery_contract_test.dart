import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary password recovery requires existing phone SMS verification', () {
    final pages =
        File('lib/features/auth/secure_onboarding_pages.dart').readAsStringSync();
    final repository =
        File('lib/features/auth/secure_onboarding_repository.dart')
            .readAsStringSync();

    expect(pages, contains('本パスワードを忘れた方'));
    expect(pages, contains('verifyPasswordResetSms'));
    expect(pages, contains('updatePrimaryPassword'));
    expect(repository, contains('requestPasswordResetSms'));
    expect(repository, contains('shouldCreateUser: false'));
    expect(repository, contains('verifyPasswordResetSms'));
    expect(repository, contains('UserAttributes(password: password)'));
  });
}
