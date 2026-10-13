import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private storage buckets have explicit file size limits', () {
    final sql = File(
      'supabase/migrations/20260920220500_bound_private_storage_file_sizes.sql',
    ).readAsStringSync();

    expect(sql, contains("'profile-photos' then 10485760"));
    expect(sql, contains("'attendance-evidence' then 15728640"));
    expect(sql, contains("'qualification-certificates' then 20971520"));
    expect(sql, contains("'communication-albums' then 20971520"));
    expect(sql, contains("'worker-documents' then 52428800"));
    expect(sql, contains("'chat-attachments' then 52428800"));
  });
}
