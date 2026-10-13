import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production auth UI exposes phone ID only', () {
    final pages =
        File('lib/features/auth/secure_onboarding_pages.dart').readAsStringSync();
    final repository =
        File('lib/features/auth/secure_onboarding_repository.dart')
            .readAsStringSync();

    expect(pages, contains('携帯電話番号（ID）'));
    expect(pages, isNot(contains('既存のメールアカウントでログイン')));
    expect(pages, isNot(contains('_existingEmailLogin')));
    expect(repository, isNot(contains('signInWithEmail')));
    expect(repository, contains('signInWithPhone'));
  });
}
