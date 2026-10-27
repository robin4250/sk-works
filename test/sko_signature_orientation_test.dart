import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/widgets/sko_orientation_policy.dart';

void main() {
  testWidgets('signature routes request only landscape and restore phone or tablet policy', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.display.size = const Size(1170, 2532);
      tester.view.display.devicePixelRatio = 3;
      addTearDown(tester.view.display.resetSize);
      addTearDown(tester.view.display.resetDevicePixelRatio);
      final orientations = <List<dynamic>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(List<dynamic>.from(call.arguments as List));
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await SkoOrientationPolicy.initialize(tester.view);
      await SkoOrientationPolicy.enterSignature();
      await SkoOrientationPolicy.enterSignature();
      await SkoOrientationPolicy.leaveSignature();
      expect(orientations.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        reason: 'one remaining signature route keeps landscape');
      await SkoOrientationPolicy.leaveSignature();
      expect(orientations, [
        ['DeviceOrientation.portraitUp'],
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        ['DeviceOrientation.portraitUp'],
      ]);
      orientations.clear();
      tester.view.display.size = const Size(2048, 2732);
      tester.view.display.devicePixelRatio = 2;
      await SkoOrientationPolicy.initialize(tester.view);
      await SkoOrientationPolicy.enterSignature();
      await SkoOrientationPolicy.leaveSignature();
      expect(orientations, [
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        [],
      ], reason: 'iPad returns to its normal platform-controlled policy');
      await SkoOrientationPolicy.leaveSignature();
      expect(orientations.length, 2, reason: 'duplicate cleanup does not overwrite policy');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await SkoOrientationPolicy.initialize(tester.view);
    }
  });
}
