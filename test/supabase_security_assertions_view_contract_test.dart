import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('security preflight checks RLS grants on tables and security-invoker on views', () {
    final source =
        File('tool/supabase_security_assertions.sql').readAsStringSync();

    expect(source, contains("c.relkind in ('r','p')"));
    expect(source, contains("c.relkind in ('v', 'm')"));
    expect(source, contains('security_invoker=true'));
  });
}
