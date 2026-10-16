import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/people/personnel_export_page.dart';
import 'package:sk_works/features/shared/pdf_pinch_pages.dart';

void main() {
  test('preview and print reuse the same frozen A4 bytes without automatic sharing', () async {
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    final preview = PersonnelExportPdfPreviewPage.previewFor(bytes);
    expect(await preview.build(PdfPageFormat.a4), same(bytes));
    expect(await preview.build(PdfPageFormat.letter), same(bytes));
    expect(preview.allowPrinting, isTrue);
    expect(preview.allowSharing, isFalse);
    expect(preview.canChangePageFormat, isFalse);
    expect(preview.canChangeOrientation, isFalse);
    expect(preview.dynamicLayout, isFalse);
  });

  testWidgets('personnel preview wires every raster page to immediate pinch', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII='));
    final preview = PersonnelExportPdfPreviewPage.previewFor(Uint8List(0));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => preview.pagesBuilder!(context, [
        for (var i = 0; i < 2; i++)
          PdfPreviewPageData(image: MemoryImage(image), width: 600, height: 800),
      ]),
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(PdfPinchPages), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final left = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final right = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await left.moveTo(center - const Offset(80, 0));
    await right.moveTo(center + const Offset(80, 0));
    await tester.pump();
    final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(1));
    await left.up();
    await right.up();
    expect(tester.takeException(), isNull);
  });
}
