import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/notifications/notification_settings_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.sko.notification_settings');
  const settings = OsNotificationSettings(channel: channel);
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Widget app() => const MaterialApp(
    home: Scaffold(body: NotificationSettingsButton(settings: settings)),
  );

  testWidgets(
    'actual OS status drives ON/OFF and settings open never pretends to toggle',
    (tester) async {
      var status = 'denied';
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return call.method == 'authorizationStatus' ? status : true;
          });
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('通知 OFF'), findsOneWidget);
      final off = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(off.onPressed, isNotNull);
      await tester.tap(find.text('通知 OFF'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'openSettings'), hasLength(1));
      expect(find.text('通知 OFF'), findsOneWidget);
      status = 'authorized';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('通知 ON'), findsOneWidget);
      final on = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(
        on.style!.side!.resolve({})!.color,
        isNot(off.style!.side!.resolve({})!.color),
      );
    },
  );

  testWidgets(
    'unrequested and unavailable authorization are never shown as ON',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => 'notDetermined');
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('通知 未許可'), findsOneWidget);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw PlatformException(code: 'unavailable'),
          );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('通知 確認不可'), findsOneWidget);
      expect(find.text('通知 ON'), findsNothing);
      await tester.tap(find.text('通知 確認不可'));
      await tester.pumpAndSettle();
      expect(find.textContaining('通知設定を開けませんでした'), findsOneWidget);
    },
  );

  test(
    'authorization parser accepts only actual known native values',
    () async {
      for (final status in ['authorized', 'provisional', 'ephemeral']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => status);
        expect(await settings.permission(), OsNotificationPermission.enabled);
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => 'appSoundEnabled');
      expect(await settings.permission(), OsNotificationPermission.unknown);
    },
  );
}
