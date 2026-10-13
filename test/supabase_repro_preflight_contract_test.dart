import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase reproducibility preflight stays non-destructive', () {
    final source =
        File('tool/supabase_repro_preflight.sh').readAsStringSync();

    expect(source, contains('supabase migration list | tee'));
    expect(source, contains('production_migration_history.txt'));
    expect(source, contains('supabase db lint --linked --fail-on error'));
    expect(source, contains('supabase db dump'));
    expect(source, contains('supabase db diff'));
    expect(source, contains('> supabase/baseline/production_storage_customizations.sql'));
    expect(source, isNot(contains('--output supabase/baseline')));
    expect(source, contains('production_storage_buckets.tsv'));
    expect(source, contains('SHA256SUMS.txt'));
    expect(source, contains('shasum -a 256'));
    expect(source, isNot(contains('supabase db reset --linked\n')));
    expect(source, isNot(contains('supabase db push\n')));
    expect(source, isNot(contains('supabase migration repair ')));
  });

  test('known historical migration drift is documented', () {
    final doc =
        File('docs/SUPABASE_REPRODUCIBILITY.md').readAsStringSync();

    expect(doc, contains('initial_sk_works_schema'));
    expect(doc, contains('add_communication_groups_and_line_bindings'));
    expect(doc, contains('add_communication_chat'));
    expect(doc, contains('add_line_bridge_foundation'));
  });
}
