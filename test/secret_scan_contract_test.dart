import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secret scan covers high-risk production credentials', () {
    final source =
        File('tool/check_no_client_secrets.sh').readAsStringSync();

    expect(source, contains('SUPABASE_SERVICE_ROLE_KEY'));
    expect(source, contains('sb_secret_'));
    expect(source, contains('LINE_CHANNEL_SECRET'));
    expect(source, contains('Bearer'));
  });
}
