import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/daily_reports/daily_report_zoom_pages.dart';
import 'package:sk_works/features/shared/pdf_pinch_pages.dart';

void main() {
  for (final daily in [false, true]) {
    for (final background in [const Color(0xfffff8e1), const Color(0xff121212)]) {
      testWidgets('${daily ? "daily" : "shared"} paper stays white over ${background.toARGB32()}',
          (tester) async {
        tester.view.physicalSize = const Size(400, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final bytes = Uint8List.fromList(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII='));
        final pages = [
          PdfPreviewPageData(image: MemoryImage(bytes), width: 300, height: 400),
        ];
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue, surface: background,
            brightness: background == const Color(0xff121212)
                ? Brightness.dark : Brightness.light,
          )),
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              backgroundColor: background,
              body: daily ? DailyReportZoomPages(pages: pages)
                  : PdfPinchPages(pages: pages),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
        final screenshot = await boundary.toImage(pixelRatio: 1);
        final data = (await screenshot.toByteData(
          format: ui.ImageByteFormat.rawRgba))!;
        Color pixel(int x, int y) {
          final offset = (y * screenshot.width + x) * 4;
          return Color.fromARGB(data.getUint8(offset + 3),
            data.getUint8(offset), data.getUint8(offset + 1),
            data.getUint8(offset + 2));
        }
        expect(pixel(200, 200), Colors.white,
          reason: 'Transparent raster must reveal white paper');
        expect(pixel(2, 2), background,
          reason: 'Surrounding preview keeps the selected theme');
        screenshot.dispose();
        });
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer));
        expect(viewer.minScale, 1);
        expect(viewer.maxScale, 5);
        final center = tester.getCenter(find.byType(InteractiveViewer));
        final left = await tester.startGesture(
          center - const Offset(20, 0), pointer: 1);
        final right = await tester.startGesture(
          center + const Offset(20, 0), pointer: 2);
        await left.moveTo(center - const Offset(80, 0));
        await right.moveTo(center + const Offset(80, 0));
        await tester.pump();
        expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
          greaterThan(1));
        await left.up();
        await right.up();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
