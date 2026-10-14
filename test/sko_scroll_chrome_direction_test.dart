import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/widgets/sko_scroll_chrome.dart';

void main() {
  testWidgets('chrome ignores small reversals and inertial rebound', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    SkoScrollChromeController.visible.value = true;
    addTearDown(() => SkoScrollChromeController.visible.value = true);
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0, maxScrollExtent: 1000, pixels: 100,
      viewportDimension: 600, axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    SkoScrollChromeController.handle(ScrollStartNotification(
      metrics: metrics, context: context, dragDetails: DragStartDetails(),
    ));
    void update(double delta, {bool finger = true}) {
      SkoScrollChromeController.handle(ScrollUpdateNotification(
        metrics: metrics, context: context, scrollDelta: delta,
        dragDetails: finger ? DragUpdateDetails(globalPosition: Offset.zero, delta: Offset(0, -delta)) : null,
      ));
    }
    for (var i = 0; i < 8; i++) {
      update(3);
      update(-3);
    }
    expect(SkoScrollChromeController.visible.value, isTrue);
    update(30);
    expect(SkoScrollChromeController.visible.value, isFalse);
    update(-30, finger: false);
    expect(SkoScrollChromeController.visible.value, isFalse);
    update(-3);
    expect(SkoScrollChromeController.visible.value, isFalse);
    update(-24);
    expect(SkoScrollChromeController.visible.value, isTrue);
  });
}
