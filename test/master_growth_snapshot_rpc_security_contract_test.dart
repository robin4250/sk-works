import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Master growth snapshot is not callable anonymously', () {
    final sql = File(
      'supabase/migrations/20260930071000_restrict_master_growth_snapshot_rpc.sql',
    ).readAsStringSync();

    expect(sql, contains('revoke all on function public.get_master_growth_snapshot()'));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('grant execute on function public.get_master_growth_snapshot()'));
    expect(sql, contains('to authenticated'));
  });
}
