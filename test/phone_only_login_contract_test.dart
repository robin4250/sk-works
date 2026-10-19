import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone and QR stay available alongside existing-account email login', () {
    final pages =
        File('lib/features/auth/secure_onboarding_pages.dart').readAsStringSync();
    final repository =
        File('lib/features/auth/secure_onboarding_repository.dart')
            .readAsStringSync();

    expect(pages, contains('携帯電話番号（ID）'));
    expect(pages, contains('従業員登録QRでログイン'));
    expect(pages, contains('登録済みのメールでログインする'));
    expect(repository, contains('signInWithEmail'));
    expect(repository, contains('signInWithPhone'));
  });
}
