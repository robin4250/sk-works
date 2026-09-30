import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('company exchange sends optional qualification certificate back image', () {
    final migration = File(
      'supabase/migrations/20260930201800_send_qualification_certificate_back_image.sql',
    ).readAsStringSync();

    expect(migration, contains('attachment_back_path'));
    expect(migration, contains('資格証裏面ファイルが見つかりません'));
    expect(migration, contains("||'（裏面）'"));
    expect(migration, contains("'qualification-certificates'"));
    expect(migration, contains("x->>'kind'='worker_qualification'"));
    expect(migration, contains("x->>'kind'='worker_personnel'"));
  });
}
