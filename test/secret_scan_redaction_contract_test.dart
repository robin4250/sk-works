import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secret scan never prints matched secret lines', () {
    final source =
        File('tool/check_no_client_secrets.sh').readAsStringSync();

    expect(source, contains('git grep -lEI'));
    expect(source, isNot(contains('git grep -nEI')));
    expect(source, contains('該当ファイル'));
  });
}
