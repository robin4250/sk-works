import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TestFlight candidate builder fails closed around production release contract', () {
    final script = File('tool/testflight_candidate.sh').readAsStringSync();
    final upload = File('tool/testflight_upload.sh').readAsStringSync();
    final finish = File('tool/testflight_finish.sh').readAsStringSync();

    expect(script, contains(r'[[ "$branch" != "main" ]]'));
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
    expect(upload, contains('APP_STORE_CONNECT_API_KEY_ID'));
    expect(upload, contains('APP_STORE_CONNECT_API_ISSUER_ID'));
    expect(upload, contains('xcrun altool'));
    expect(upload, contains('--upload-app'));
    expect(upload, contains('git rev-parse origin/main'));
    expect(finish, contains('bash tool/testflight_candidate.sh'));
    expect(finish, contains('bash tool/testflight_upload.sh'));
    expect(finish, contains('Runner.xcarchive'));
    expect(finish, contains('open "$archive"'));
    expect(script, contains('--build-name='));
    expect(script, contains('--build-number='));
    expect(script, contains('CFBundleShortVersionString'));
    expect(script, contains('CFBundleVersion'));
    expect(script, contains('SKO_TESTFLIGHT_BUILD_NUMBER'));
  });
}
