import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English pack covers finance status labels', () {
    final english = File(
      'lib/international/languages/en/english_language_pack.dart',
    ).readAsStringSync();

    for (final key in [
      '給料一覧',
      '確認済み',
      '未確定',
      '支払証明書',
      '下書き',
      '確定',
    ]) {
      expect(english, contains("'$key':"));
    }
  });
}
