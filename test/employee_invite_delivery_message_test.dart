import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only native handoff spies; no share sheet or SMS app is opened.
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:sk_works/features/people/employee_invite_delivery_message.dart';
import 'package:sk_works/features/people/employee_initial_registration_page.dart';
import 'package:sk_works/features/people/employee_invite_page.dart';

import 'employee_invite_context_sdk_test.dart' as fixture;

// Synthetic syntax input only. Never registered, fetched or delivered.
const syntheticJoin = 'https://testflight.apple.com/join/AbC123xy';

class ShareCapture extends SharePlatform {
  final texts = <String?>[];
  @override
  Future<ShareResult> share(ShareParams params) async {
    texts.add(params.text);
    return ShareResult.unavailable;
  }
}

class SmsCapture extends UrlLauncherPlatform {
  final uris = <Uri>[];
  @override
  get linkDelegate => null;
  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    uris.add(Uri.parse(url));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final shares = ShareCapture();
  final sms = SmsCapture();
  SharePlatform.instance = shares;
  UrlLauncherPlatform.instance = sms;
  setUp(() {
    shares.texts.clear();
    sms.uris.clear();
  });

  test('canonical participation URL preserves the case of the code', () {
    expect(employeeInviteTestFlightUrl('  $syntheticJoin \n'), syntheticJoin);
    expect(employeeInviteTestFlightUrl('https://testflight.apple.com/join/a'),
        'https://testflight.apple.com/join/a');
  });

  for (final invalid in <String?>[
    null,
    '',
    '未設定',
    'https://testflight.apple.com/join/...',
    'https://testflight.apple.com/join/YOUR_CODE',
    'https://testflight.apple.com/join/<code>',
    'https://testflight.apple.com/join/',
    'http://testflight.apple.com/join/AbC123xy',
    'https://testflight.apple.com.evil.invalid/join/AbC123xy',
    'https://user:password@testflight.apple.com/join/AbC123xy',
    'https://testflight.apple.com:443/join/AbC123xy',
    '$syntheticJoin?tracking=1',
    '$syntheticJoin#fragment',
    '$syntheticJoin/',
    'https://testflight.apple.com/join/AbC%31123xy',
    'https://testflight.apple.com/join/AbC123xy/extra',
    'https://TESTFLIGHT.apple.com/join/AbC123xy',
    'HTTPS://testflight.apple.com/join/AbC123xy',
  ]) {
    test('unsupported or example participation value is omitted: $invalid', () {
      expect(employeeInviteTestFlightUrl(invalid), isNull);
      final message = employeeInviteDeliveryMessage(
        name: 'Synthetic Employee',
        phone: '+817000000000',
        temporaryPassword: 'synthetic-private-password',
        testFlightUrl: invalid,
      );
      expect(message, isNot(contains('TestFlight: ')));
      if (invalid != null && invalid.startsWith('http')) {
        expect(message, isNot(contains(invalid)));
      }
      expect(message, contains(employeeInviteInstallationGuide));
      expect(message, contains('TestFlight参加URLは未設定'));
    });
  }

  for (final english in [false, true]) {
    test('shared delivery text keeps guide and credentials, English=$english', () {
      final message = employeeInviteDeliveryMessage(
        name: 'Synthetic Employee',
        phone: '+817000000000',
        temporaryPassword: 'synthetic-private-password',
        testFlightUrl: syntheticJoin,
        english: english,
      );
      expect(message.split(syntheticJoin).length - 1, 1);
      expect(message.split(employeeInviteInstallationGuide).length - 1, 1);
      expect(message, contains('Synthetic Employee'));
      expect(message, contains('+817000000000'));
      expect(message, contains('synthetic-private-password'));
      expect(message, contains(english ? 'first sign-in' : '初回ログイン後'));
    });
  }

  for (final initialPage in [false, true]) {
    for (final url in <String?>[
      syntheticJoin,
      null,
      'https://testflight.apple.com/join/...',
    ]) {
      testWidgets('both native handoffs use the same safe body: initial=$initialPage URL=$url', (tester) async {
        final f = (await tester.runAsync(() async => fixture.Fixture()))!;
        addTearDown(() async => tester.runAsync(f.close));
        f.response = {...fixture.result(), 'testFlightUrl': url};
        await tester.runAsync(f.login);
        await tester.pumpWidget(MaterialApp(
          home: initialPage
              ? EmployeeInitialRegistrationPage(repository: f.repository)
              : EmployeeInvitePage(repository: f.repository),
        ));
        await tester.pumpAndSettle();
        if (initialPage) {
          await tester.ensureVisible(find.text('送信'));
          await tester.runAsync(() async {
            await tester.tap(find.text('送信'));
            await f.repository.completed.future.timeout(const Duration(seconds: 5));
            await f.repository.refreshed.future.timeout(const Duration(seconds: 5));
          });
        } else {
          await tester.enterText(find.byType(TextField).at(0), 'Synthetic Employee');
          await tester.enterText(find.byType(TextField).at(1), '07000000000');
          final create = find.byWidgetPredicate((w) => w is FilledButton);
          await tester.ensureVisible(create.first);
          await tester.runAsync(() async {
            await tester.tap(create.first);
            await f.repository.completed.future.timeout(const Duration(seconds: 5));
          });
        }
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        ).first;
        final shareLabel = initialPage ? 'LINE・メッセージ等で共有' : 'SMS・メッセージなどで共有';
        await tester.scrollUntilVisible(find.text(shareLabel), 200,
            maxScrolls: 30, scrollable: scrollable);
        await tester.tap(find.text(shareLabel));
        await tester.pumpAndSettle();
        final smsLabel = initialPage ? 'この従業員へSMSを作成' : 'SMS送信';
        await tester.scrollUntilVisible(find.text(smsLabel), -200,
            maxScrolls: 30, scrollable: scrollable);
        await tester.tap(find.text(smsLabel));
        await tester.pumpAndSettle();
        final expected = employeeInviteDeliveryMessage(
          name: 'Synthetic Employee',
          phone: '+817000000000',
          temporaryPassword: fixture.fixturePassword,
          testFlightUrl: url,
        );
        expect(shares.texts, [expected]);
        expect(sms.uris, hasLength(1));
        expect(sms.uris.single.scheme, 'sms');
        expect(sms.uris.single.path, '+817000000000');
        expect(sms.uris.single.queryParameters['body'], expected);
        expect(f.invokes, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
