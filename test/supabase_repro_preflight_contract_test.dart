import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase reproducibility preflight stays non-destructive', () {
    final source =
        File('tool/supabase_repro_preflight.sh').readAsStringSync();

    expect(source, contains('supabase migration list --linked'));
    expect(source, contains('supabase db lint --linked --fail-on error'));
    expect(source, contains('supabase db dump'));
    expect(source, contains('supabase db diff'));
    expect(source, isNot(contains('supabase db reset --linked\n')));
    expect(source, isNot(contains('supabase db push\n')));
    expect(source, isNot(contains('supabase migration repair ')));
  });
}
