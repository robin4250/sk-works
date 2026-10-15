import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/daily_reports/daily_report_pdf_service.dart';
import 'package:sk_works/features/daily_reports/daily_report_zoom_pages.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

void main() {
  test('portrait and landscape capture dimensions survive existing RPC wrapper', () {
    for (final size in [const Size(320, 640), const Size(900, 240), const Size(844.5, 232.75)]) {
      final result = SignatureResult(signerName: '署名', canvasSize: size,
        strokes: [[const Offset(.1, .2), const Offset(.9, .8)]]);
      final saved = jsonDecode(jsonEncode({'strokes': result.toJson()}));
      expect(SignatureResult.sizeFromJson(saved), size);
      expect(SignatureResult.fromJson(saved), result.strokes);
      final svg = DailyReportPdfService.signatureSvg(saved)!;
      final dimensions = RegExp(r'viewBox="0 0 ([0-9.]+) ([0-9.]+)"').firstMatch(svg)!;
      expect(double.parse(dimensions.group(1)!), size.width);
      expect(double.parse(dimensions.group(2)!), size.height);
      expect(svg, contains('${(size.width * .9).toStringAsFixed(1)},${(size.height * .8).toStringAsFixed(1)}'));
    }
  });

  test('legacy strokes keep historical PDF proportions without invented dimensions', () {
    final old = [[{'x': .1, 'y': .2}, {'x': .9, 'y': .8}]];
    expect(SignatureResult.sizeFromJson(old), isNull);
    expect(DailyReportPdfService.signatureSvg(old), contains('viewBox="0 0 400 120"'));
  });

  testWidgets('capture rotation preserves logical canvas instead of stretching strokes', (tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: SignatureCapturePage(initialSignerName: '記入者')));
    final paint = find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is SignaturePainter);
    await tester.dragFrom(tester.getCenter(paint), const Offset(60, 15));
    await tester.pump();
    final before = (tester.widget<CustomPaint>(paint).painter! as SignaturePainter).canvasSize!;
    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    final after = tester.getSize(paint);
    expect(after.aspectRatio, closeTo(before.aspectRatio, .001));
    expect(find.textContaining('端末を横向き'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two-finger pinch zooms without double tap and reports zoom state', (tester) async {
    final bytes = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII='));
    final changes = <bool>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DailyReportZoomPages(
      pages: [PdfPreviewPageData(image: MemoryImage(bytes), width: 600, height: 800)], onZoomChanged: changes.add))));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final right = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await left.moveTo(center - const Offset(80, 0));
    await right.moveTo(center + const Offset(80, 0));
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(1));
    expect(changes, contains(true));
    await left.up(); await right.up();
  });
}
