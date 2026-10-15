import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/widgets/sko_orientation_policy.dart';

void main() {
  testWidgets('only iPhone signatures rotate and restore normal policy on exit', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.display.size = const Size(1170, 2532);
    tester.view.display.devicePixelRatio = 3;
    addTearDown(tester.view.display.resetSize);
    addTearDown(tester.view.display.resetDevicePixelRatio);
    final orientations = <List<dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') orientations.add(List<dynamic>.from(call.arguments as List));
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await SkoOrientationPolicy.initialize(tester.view);
    await SkoOrientationPolicy.enterSignature();
    await SkoOrientationPolicy.leaveSignature();
    expect(orientations, [
      ['DeviceOrientation.portraitUp'],
      ['DeviceOrientation.portraitUp', 'DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      ['DeviceOrientation.portraitUp'],
    ]);
    orientations.clear();
    tester.view.display.size = const Size(2048, 2732);
    tester.view.display.devicePixelRatio = 2;
    await SkoOrientationPolicy.initialize(tester.view);
    await SkoOrientationPolicy.enterSignature();
    await SkoOrientationPolicy.leaveSignature();
    expect(orientations, isEmpty, reason: 'iPad keeps its existing orientation policy');
  });
}
