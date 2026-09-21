import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DB audit asserts every private Storage size limit', () {
    final source =
        File('tool/supabase_security_assertions.sql').readAsStringSync();

    expect(source, contains("'profile-photos'::text, 10485760::bigint"));
    expect(source, contains("'attendance-evidence'::text, 15728640::bigint"));
    expect(source, contains("'qualification-certificates'::text, 20971520::bigint"));
    expect(source, contains("'communication-albums'::text, 20971520::bigint"));
    expect(source, contains("'worker-documents'::text, 52428800::bigint"));
    expect(source, contains("'chat-attachments'::text, 52428800::bigint"));
    expect(source, contains('security_invoker=true'));
    expect(source, contains("has_schema_privilege('authenticated', 'public', 'CREATE')"));
    expect(source, contains('SECURITY DEFINER function without explicit search_path'));
    expect(source, contains('exposed public view/materialized view may bypass RLS'));
  });
}
