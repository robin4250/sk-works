import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/auth/existing_google_login.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('Mac callback entry follows explicit candidate gate', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(ExistingGoogleLogin.supportedPlatform,
        const bool.fromEnvironment('SKO_MACOS_GOOGLE_V1', defaultValue: false));
  });
  test('Existing iOS entry remains available', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(ExistingGoogleLogin.supportedPlatform, isTrue);
    expect(ExistingGoogleLogin.nativeRedirect, 'com.skworks.sko://login-callback/');
  });
  test('Other platforms remain closed', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(ExistingGoogleLogin.supportedPlatform, isFalse);
  });
}
