import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/settings/master_device_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(MasterDevicePlatform.channel, null));
  for (final type in ['ipad', 'iphone']) {
    test('$type is registered with its actual iOS classification', () async {
      messenger.setMockMethodCallHandler(MasterDevicePlatform.channel, (call) async {
        expect(call.method, 'deviceType'); return type;
      });
      final device = await MasterDevicePlatform.detect(operatingSystem: 'ios');
      expect(device.type, type);
      expect(device.name, contains(type == 'ipad' ? 'iPad' : 'iPhone'));
    });
  }
  test('unknown or unavailable iOS classification cannot silently become iPhone', () async {
    messenger.setMockMethodCallHandler(MasterDevicePlatform.channel, (_) async => 'unknown');
    await expectLater(MasterDevicePlatform.detect(operatingSystem: 'ios'), throwsStateError);
    messenger.setMockMethodCallHandler(MasterDevicePlatform.channel, null);
    await expectLater(MasterDevicePlatform.detect(operatingSystem: 'ios'), throwsA(isA<MissingPluginException>()));
  });
  test('MacBook uses Mac classification without an iOS channel', () async {
    final device = await MasterDevicePlatform.detect(operatingSystem: 'macos');
    expect(device.type, 'mac'); expect(device.name, contains('MacBook'));
  });
}
