import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release gate blocks destructive Supabase helper commands', () {
    final gate = File('tool/pre_device_release_gate.sh').readAsStringSync();
    final guard =
        File('tool/check_no_destructive_supabase_commands.sh').readAsStringSync();

    expect(gate, contains('bash tool/check_no_destructive_supabase_commands.sh'));
    expect(guard, contains('supabase[[:space:]]+db[[:space:]]+reset'));
    expect(guard, contains('supabase[[:space:]]+db[[:space:]]+push'));
    expect(guard, contains('supabase[[:space:]]+migration[[:space:]]+repair'));
    expect(guard, contains('tool/*.sh'));
  });
}
