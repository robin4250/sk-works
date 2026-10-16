import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:sk_works/features/people/personnel_export_page.dart';
import 'package:sk_works/features/shared/pdf_pinch_pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.nfet.printing');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => {
        'canPrint': true, 'canRaster': false, 'canShare': true,
        'canConvertHtml': false, 'directPrint': false, 'dynamicLayout': false,
      });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
  });

  testWidgets('normal route holds immutable bytes and a stable preview callback', (tester) async {
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    final page = PersonnelExportPdfPreviewPage(bytes: bytes);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    final frozen = await preview.build(PdfPageFormat.a4);
    expect(frozen, orderedEquals(bytes));
    bytes[0] = 0;
    expect((await preview.build(PdfPageFormat.letter))[0], 37);
    expect(preview.allowPrinting, isTrue);
    expect(preview.allowSharing, isFalse);
    expect(preview.canChangePageFormat, isFalse);
    expect(preview.canChangeOrientation, isFalse);
    expect(preview.dynamicLayout, isFalse);
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: page));
    await tester.pumpAndSettle();
    expect(tester.widget<PdfPreview>(find.byType(PdfPreview)).build, same(preview.build));
    expect(tester.takeException(), isNull);
  });

  testWidgets('personnel preview wires every raster page to immediate pinch', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII='));
    await tester.pumpWidget(MaterialApp(home: PersonnelExportPdfPreviewPage(bytes: Uint8List(0))));
    await tester.pumpAndSettle();
    final custom = tester.widget<PdfPreviewCustom>(find.byType(PdfPreviewCustom));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => custom.pagesBuilder!(context, [
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
  testWidgets('closing preview returns to selection without losing selected people', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PersonnelExportPage(
      title: 'Export', workers: [PersonnelExportWorker(id: 'worker', name: 'Employee')],
      operation: PersonnelExportOperation.print, initialWorkerIds: ['worker'],
    )));
    await tester.pumpAndSettle();
    final action = find.text('内容を確認して印刷');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.text('印刷する'));
    await tester.pumpAndSettle();
    expect(find.byType(PersonnelExportPdfPreviewPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PersonnelExportPage), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
    expect(find.byType(PersonnelExportPdfPreviewPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('native print success is the only successful preview route result', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      TextButton(onPressed: () async {
        result = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => PersonnelExportPdfPreviewPage(bytes: Uint8List(0))));
      }, child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final preview = tester.widget<PdfPreview>(find.byType(PdfPreview));
    preview.onPrintError!(tester.element(find.byType(PdfPreview)), StateError('synthetic'));
    await tester.pump();
    expect(result, isNull);
    expect(find.byType(PersonnelExportPdfPreviewPage), findsOneWidget);
    preview.onPrinted!(tester.element(find.byType(PdfPreview)));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(PersonnelExportPdfPreviewPage), findsNothing);
  });

}
