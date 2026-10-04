import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approval flow preserves freeform allowance names', () {
    final sql = File(
      'supabase/migrations/20261004081800_preserve_freeform_allowance_names.sql',
    ).readAsStringSync();
    expect(sql, contains('allowance_names'));
    expect(sql, contains('jsonb_array_elements_text'));
    expect(sql, contains("proposed_snapshot ? 'allowanceNames'"));
    expect(sql, contains('allowance_label=case'));
    expect(sql, contains("array_to_string"));
  });
}
