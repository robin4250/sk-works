import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SMS password recovery updates password immediately after OTP', () {
    final source =
        File('lib/features/auth/secure_onboarding_pages.dart')
            .readAsStringSync();

    final verifyIndex = source.indexOf('verifyPasswordResetSms(');
    final updateIndex =
        source.indexOf('updatePrimaryPassword(_password.text)', verifyIndex);
    final signOutIndex = source.indexOf('repository.signOut()', updateIndex);
    final authIndex = source.indexOf('widget.onAuthenticated()', updateIndex);

    expect(source, isNot(contains('_passwordResetVerified')));
    expect(verifyIndex, greaterThanOrEqualTo(0));
    expect(updateIndex, greaterThan(verifyIndex));
    expect(signOutIndex, greaterThan(updateIndex));
    expect(authIndex, greaterThan(updateIndex));
    expect(
      source,
      contains('SMS本人確認に成功した直後、この新しい本パスワードへ更新します。'),
    );
  });
}
