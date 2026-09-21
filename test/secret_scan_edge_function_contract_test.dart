import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracked-secret scan includes Edge Function sources', () {
    final source = File('tool/check_no_client_secrets.sh').readAsStringSync();

    expect(source, isNot(contains(":!docs/**")));
    expect(
      source,
      isNot(contains(':!supabase/functions/line-webhook/index.ts')),
    );
    expect(source, contains('SUPABASE_SERVICE_ROLE_KEY'));
    expect(source, contains('LINE_CHANNEL_SECRET'));
    expect(source, contains('sb_secret_'));
    expect(source, contains('JWT-like secret absent'));
  });
}
