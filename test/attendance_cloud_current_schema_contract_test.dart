import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance cloud repository does not query removed signature columns', () {
    final source = File(
      'lib/features/attendance/attendance_cloud_repository.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('signer_name')));
    expect(source, isNot(contains('signature_json')));
    expect(source, isNot(contains('signed_at')));
    expect(source, contains("'signerName': null"));
    expect(source, contains("'signatureJson': null"));
    expect(source, contains("'signedAt': null"));
    expect(source, contains("workers(name), sites(name)"));
  });
}
