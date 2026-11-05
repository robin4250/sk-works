import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing in-memory SDK/PKCE/browser fixtures. No live OAuth/browser transport.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:sk_works/features/auth/existing_google_login.dart';
import 'package:sk_works/features/auth/app_auth_mutation_gateway.dart';
import 'existing_google_gateway_boundary_test.dart' as native;
import 'app_auth_mutation_gateway_test.dart' as auth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('SKO_MAC_EXISTING_GOOGLE_LOGIN_ENABLED', defaultValue: false);
  final mode = enabled ? 'ON synthetic handoff' : 'OFF no handoff';
  tearDown(() { debugDefaultTargetPlatformOverride = null; });

  test('Mac gate $mode leaves iOS supported and other platforms closed', () {
    expect(ExistingGoogleLogin.macEnabled, enabled);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(ExistingGoogleLogin.supportedPlatform,
          platform == TargetPlatform.iOS || (platform == TargetPlatform.macOS && enabled));
    }
  });

  test('Mac $mode preserves SDK Google PKCE request and chooses external browser only when enabled', () async {
    final wire = auth.Wire();
    final storage = native.MemoryPkce();
    final client = native.nativeClient(wire, pkce: storage);
    final previous = UrlLauncherPlatform.instance;
    final browser = native.BrowserSpy();
    UrlLauncherPlatform.instance = browser;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      if (!enabled) {
        await expectLater(ExistingGoogleLogin(client).launch(), throwsUnsupportedError);
        expect(storage.writes, 0);
        expect(browser.urls, isEmpty);
      } else {
        expect(await ExistingGoogleLogin(client).launch(), true);
        expect(browser.urls, hasLength(1));
        final request = browser.urls.single;
        expect(request.origin, 'https://native-google-fixture.invalid');
        expect(request.path, '/auth/v1/authorize');
        expect(request.queryParameters['provider'], 'google');
        expect(request.queryParameters['redirect_to'], ExistingGoogleLogin.nativeRedirect);
        expect(request.queryParameters['prompt'], 'select_account');
        expect(request.queryParameters['code_challenge'], isNotEmpty);
        expect(request.queryParameters['code_challenge_method']?.toLowerCase(), 's256');
        expect(storage.writes, 1);
        expect(browser.options.single.mode, PreferredLaunchMode.externalApplication);
      }
      expect(wire.calls, isEmpty); // URL generation/handoff never signs up or authenticates.
      expect(client.auth.currentSession, isNull);
    } finally {
      UrlLauncherPlatform.instance = previous;
      await client.dispose();
      await wire.client.dispose();
    }
  });

  test('Mac $mode cannot hand off after logout during pending PKCE storage', () async {
    final wire = auth.Wire();
    final storage = native.MemoryPkce()..writeGate = Completer<void>();
    final client = native.nativeClient(wire, pkce: storage);
    final previous = UrlLauncherPlatform.instance;
    final browser = native.BrowserSpy();
    UrlLauncherPlatform.instance = browser;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      if (!enabled) {
        await expectLater(ExistingGoogleLogin(client).launch(), throwsUnsupportedError);
        expect(storage.writes, 0);
      } else {
        final pending = ExistingGoogleLogin(client).launch();
        final rejected = expectLater(pending, throwsStateError);
        for (var n = 0; n < 40 && storage.writes == 0; n++) {
          await Future<void>.value();
        }
        expect(storage.writes, 1);
        await AppAuthMutationGateway.forClient(client).signOut();
        storage.writeGate!.complete();
        await rejected;
      }
      expect(browser.urls, isEmpty);
      expect(client.auth.currentSession, isNull);
    } finally {
      if (!storage.writeGate!.isCompleted) storage.writeGate!.complete();
      UrlLauncherPlatform.instance = previous;
      await client.dispose();
      await wire.client.dispose();
    }
  });
}
