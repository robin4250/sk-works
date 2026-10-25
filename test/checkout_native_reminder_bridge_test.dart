import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/attendance/checkout_native_reminder_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.sko.checkout-reminders');
  const codec = StandardMethodCodec();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late CheckoutNativeReminderBridge bridge;
  final calls = <MethodCall>[];
  Object? response;
  PlatformException? failure;

  Future<Object?> nativeEvent(String method, Object? arguments) async {
    final completer = Completer<Object?>();
    // Exercise the actual inbound MethodChannel decoder, not a private method.
    // ignore: deprecated_member_use
    await messenger.handlePlatformMessage(channel.name, codec.encodeMethodCall(MethodCall(method, arguments)), (reply) {
      completer.complete(reply == null ? null : codec.decodeEnvelope(reply));
    });
    return completer.future;
  }

  setUp(() {
    calls.clear();
    response = null;
    failure = null;
    bridge = CheckoutNativeReminderBridge(channel: channel, supported: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failure != null) throw failure!;
      return response;
    });
  });

  tearDown(() async {
    await bridge.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('status is read-only and does not request permission', () async {
    response = 'denied';
    expect(await bridge.authorizationStatus(), NativeReminderAuthorization.denied);
    expect(calls.single.method, 'status');
  });
  test('explicit permission returns actual provisional state', () async {
    response = 'provisional';
    expect(await bridge.requestPermission(), NativeReminderAuthorization.provisional);
    expect(calls.single.method, 'requestPermission');
  });
  test('unknown and malformed status are not authorized', () async {
    for (final value in <Object?>['futureStatus', true, <String, String>{}, null]) {
      response = value;
      expect(await bridge.authorizationStatus(), NativeReminderAuthorization.unknown);
    }
  });
  test('unsupported platform never invokes native methods', () async {
    final unsupported = CheckoutNativeReminderBridge(channel: const MethodChannel('unsupported'), supported: false);
    expect(await unsupported.authorizationStatus(), NativeReminderAuthorization.unsupported);
    expect(await unsupported.schedule(sourceId: 'source', fireAt: DateTime.utc(2026)), NativeReminderScheduleResult.unavailable);
    expect(await unsupported.cancelAll(), false);
    expect(await unsupported.consumePendingTap(), null);
    expect(calls, isEmpty);
    await unsupported.dispose();
  });
  test('schedule passes absolute instant and generic text only', () async {
    response = 'scheduled';
    final at = DateTime.parse('2026-10-27T17:30:00+09:00');
    expect(await bridge.schedule(sourceId: 'actor:worker:2026-10-27', fireAt: at), NativeReminderScheduleResult.scheduled);
    expect(calls.single.method, 'schedule');
    expect(calls.single.arguments, <String, Object>{
      'sourceId': 'actor:worker:2026-10-27',
      'fireAtEpochMs': at.toUtc().millisecondsSinceEpoch,
      'title': 'SKO｜退勤の確認',
      'body': '退勤予定時刻です。勤務状況を確認してください。',
    });
  });
  test('permission denied is distinct from scheduling success', () async {
    failure = PlatformException(code: 'permission_denied');
    expect(await bridge.schedule(sourceId: 'source', fireAt: DateTime.now()), NativeReminderScheduleResult.permissionDenied);
  });
  test('native cancellation while awaiting authorization is not success', () async {
    failure = PlatformException(code: 'cancelled');
    expect(await bridge.schedule(sourceId: 'source', fireAt: DateTime.now()), NativeReminderScheduleResult.cancelled);
  });
  test('failed and malformed native acknowledgments stay unavailable', () async {
    response = true;
    expect(await bridge.schedule(sourceId: 'source', fireAt: DateTime.now()), NativeReminderScheduleResult.unavailable);
    failure = PlatformException(code: 'schedule_failed');
    expect(await bridge.schedule(sourceId: 'source', fireAt: DateTime.now()), NativeReminderScheduleResult.unavailable);
  });
  test('bad source refuses before native scheduling', () async {
    for (final source in <String>['', 'person@example.com', 'source/path', 'a' * 161]) {
      await expectLater(bridge.schedule(sourceId: source, fireAt: DateTime.now()), throwsArgumentError);
    }
    expect(calls, isEmpty);
  });
  test('feature cancellation passes only source and cancelAll is separate', () async {
    response = true;
    expect(await bridge.cancel('source'), true);
    expect(calls.last.arguments, <String, String>{'sourceId': 'source'});
    expect(await bridge.cancelAll(), true);
    expect(calls.last.method, 'cancelAll');
    expect(calls.last.arguments, isNull);
  });
  test('replanning preserves pending tap until explicit server acknowledgment', () async {
    response = true;
    expect(await bridge.cancelAll(preservePendingTap: true), true);
    expect(calls.last.arguments, <String, Object>{'preservePendingTap': true});
    expect(await bridge.acknowledgePendingTap('source'), true);
    expect(calls.last.method, 'acknowledgePendingTap');
    expect(calls.last.arguments, <String, String>{'sourceId': 'source'});
  });
  test('cancel failure is not presented as successful cleanup', () async {
    failure = PlatformException(code: 'unavailable');
    expect(await bridge.cancelAll(), false);
  });
  test('tap with no listener remains unacknowledged for cold start', () async {
    expect(await nativeEvent('notificationTapped', 'actor:worker:day'), false);
    response = 'actor:worker:day';
    expect(await bridge.consumePendingTap(), 'actor:worker:day');
    expect(calls.single.method, 'consumePendingTap');
  });
  test('tap only emits source to caller and invokes no checkout RPC', () async {
    final seen = <String>[];
    final subscription = bridge.taps.listen(seen.add);
    expect(await nativeEvent('notificationTapped', 'source'), false);
    expect(seen, <String>['source']);
    expect(calls, isEmpty);
    await subscription.cancel();
  });
  test('due event is distinct from a user tap', () async {
    final due = <String>[];
    final taps = <String>[];
    final a = bridge.due.listen(due.add);
    final b = bridge.taps.listen(taps.add);
    expect(await nativeEvent('notificationDue', 'source'), true);
    expect(due, <String>['source']);
    expect(taps, isEmpty);
    await a.cancel();
    await b.cancel();
  });
  test('malformed events and pending sources fail closed', () async {
    final seen = <String>[];
    final subscription = bridge.taps.listen(seen.add);
    for (final invalid in <Object?>[null, true, <String, String>{'sourceId': 'source'}, 'bad/source']) {
      expect(await nativeEvent('notificationTapped', invalid), false);
      response = invalid;
      expect(await bridge.consumePendingTap(), null);
    }
    expect(await nativeEvent('unexpected', 'source'), false);
    expect(seen, isEmpty);
    await subscription.cancel();
  });
  test('disposed bridge rejects scheduling and late permission success', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final status = bridge.requestPermission();
    await Future<void>.delayed(Duration.zero);
    await bridge.dispose();
    pending.complete('authorized');
    expect(await status, NativeReminderAuthorization.unavailable);
    expect(await bridge.schedule(sourceId: 'source', fireAt: DateTime.now()), NativeReminderScheduleResult.unavailable);
  });
}
