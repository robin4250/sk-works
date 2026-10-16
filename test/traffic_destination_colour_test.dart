import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/traffic/traffic_destination_icon.dart';
import 'package:sk_works/features/traffic/traffic_link_policy.dart';

void main() {
  testWidgets('20px destination signs render distinct colours and disabled signs stay grey', (tester) async {
    final boundaryKey = GlobalKey();
    for (final enabled in [true, false]) {
      for (final destination in TrafficDestination.values) {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
          child: RepaintBoundary(key: boundaryKey, child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xff777777)),
            child: TrafficDestinationIcon(destination: destination, enabled: enabled),
          )),
        ))));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(TrafficDestinationIcon)), const Size(20, 20));
        final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 4);
          try { return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List(); }
          finally { image.dispose(); }
        });
        var coloured = 0, opaque = 0, silver = 0;
        final palette = <int>{};
        for (var i = 0; i < pixels!.length; i += 4) {
          final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2], a = pixels[i + 3];
          if (a < 230) continue;
          opaque++;
          if (r > 170 && (r - g).abs() + (g - b).abs() <= 2) silver++;
          palette.add((r << 16) | (g << 8) | b);
          final matches = switch(destination) {
            TrafficDestination.nearestStation => r > g + 60 && g > b + 10,
            TrafficDestination.trainTransfer => g > 170 && g > r + 30 && g > b + 20,
            TrafficDestination.busStop => r > g + 60 && g > b + 60,
          };
          if (enabled && matches) coloured++;
          if (!enabled) expect((r - g).abs() + (g - b).abs(), lessThanOrEqualTo(2));
        }
        expect(opaque, greaterThan(40), reason: 'The sign must actually render at compact size');
        if (enabled) {
          expect(coloured, greaterThan(20), reason: 'Station brick, bright yellow-green train stripe and orange bus remain recognizable');
          if (destination == TrafficDestination.trainTransfer) expect(silver, greaterThan(20), reason: 'The side-view train keeps its silver body');
          expect(palette.length, greaterThan(1), reason: 'Vehicle body and sign details must remain distinguishable');
        } else { expect(coloured, 0); }
      }
    }
  });
}
