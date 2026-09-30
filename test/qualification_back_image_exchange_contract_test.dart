import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('qualification exchange includes optional certificate back image', () {
    final sql = File(
      'supabase/migrations/20260930201810_send_qualification_certificate_back_image.sql',
    ).readAsStringSync();

    expect(sql, contains('attachment_back_path'));
    expect(sql, contains('資格証裏面ファイルが見つかりません'));
    expect(sql, contains('qualification-certificates'));
    expect(sql, contains('company_path'));
    expect(sql, contains("m.role::text in ('owner','admin')"));
  });
}
