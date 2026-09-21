import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secret scan workflow runs without path exclusions', () {
    final source =
        File('.github/workflows/secret-scan.yml').readAsStringSync();

    expect(source, contains('push:'));
    expect(source, contains('pull_request:'));
    expect(source, isNot(contains('paths-ignore:')));
    expect(source, isNot(contains('paths:')));
    expect(source, contains('bash tool/check_no_client_secrets.sh'));
  });
}
