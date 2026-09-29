import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification page must not ship with prototype registration action', () {
    final source =
        File('lib/features/qualifications/qualification_page.dart').readAsStringSync();

    expect(
      source.contains('資格マスターから選択して作業員へ登録するフォームを次段階で接続します'),
      isFalse,
      reason: 'TestFlight candidate must use the real qualification registration flow, not a prototype notice.',
    );
  });
}
