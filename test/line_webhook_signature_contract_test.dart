import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LINE webhook requires a valid LINE HMAC signature', () {
    final source =
        File('supabase/functions/line-webhook/index.ts').readAsStringSync();

    expect(source, contains('x-line-signature'));
    expect(source, contains('HMAC'));
    expect(source, contains('SHA-256'));
    expect(source, contains('LINE_CHANNEL_SECRET'));
    expect(source, contains('Invalid signature'));
    expect(source, contains('status: 401'));
    expect(source, contains('constantTimeEqual'));
    expect(source, isNot(contains('receivedSignature !== expectedSignature')));

    final signatureCheck = source.indexOf('constantTimeEqual(receivedSignature, expectedSignature)');
    final firstDatabaseCall = source.indexOf('rest("line_webhook_events');
    expect(signatureCheck, greaterThanOrEqualTo(0));
    expect(firstDatabaseCall, greaterThan(signatureCheck));
  });
}
