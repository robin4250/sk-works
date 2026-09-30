import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/international/countries/jp/japan_phone_rules.dart';

void main() {
  test('Japan phone rules preserve current JP mobile behavior', () {
    expect(JapanPhoneRules.normalize('090-1234-5678'), '+819012345678');
    expect(JapanPhoneRules.normalize('+81 80 1111 2222'), '+818011112222');
    expect(JapanPhoneRules.isSupportedMobile('070-3333-4444'), isTrue);
    expect(JapanPhoneRules.isSupportedMobile('03-1234-5678'), isFalse);
  });

  test('secure onboarding delegates Japan-specific phone behavior', () {
    final repository = File(
      'lib/features/auth/secure_onboarding_repository.dart',
    ).readAsStringSync();

    expect(repository, contains('JapanPhoneRules.normalize(raw)'));
    expect(repository, contains('JapanPhoneRules.isSupportedMobile(raw)'));
    expect(repository, isNot(contains("digits.startsWith('81')")));
    expect(repository, isNot(contains("RegExp(r'^\\+81(?:70|80|90)")));
  });
}
