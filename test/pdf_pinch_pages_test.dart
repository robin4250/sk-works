import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/shared/pdf_pinch_pages.dart';

void main() {
  testWidgets('PDF pages pinch immediately and retain all document pages', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII='));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PdfPinchPages(
      pages: [for (var i = 0; i < 2; i++)
        PdfPreviewPageData(image: MemoryImage(bytes), width: 600, height: 800)]))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final right = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await left.moveTo(center - const Offset(80, 0));
    await right.moveTo(center + const Offset(80, 0));
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(1));
    await left.up(); await right.up();
    expect(tester.takeException(), isNull);
  });
}
