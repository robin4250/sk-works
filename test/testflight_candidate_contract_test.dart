import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TestFlight candidate builder fails closed around production release contract', () {
    final script = File('tool/testflight_candidate.sh').readAsStringSync();

    expect(script, contains('branch != "main"'));
    expect(script, contains('git rev-parse origin/main'));
    expect(script, contains('bash tool/prepare_ios.sh'));
    expect(script, contains('bash tool/testflight_preflight.sh'));
    expect(script, contains('flutter build ipa'));
    expect(script, contains('--release'));
    expect(script, contains('--export-method app-store'));
    expect(script, contains('SUPABASE_URL'));
    expect(script, contains('SUPABASE_PUBLISHABLE_KEY'));
    expect(script, contains('com.skworks.skWorks'));
    expect(script, isNot(contains('com.robin4250.sko')));
    expect(script, contains('build/ios/archive/Runner.xcarchive'));
    expect(script, contains('build/ios/ipa'));
  });
}
