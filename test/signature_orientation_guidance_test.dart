import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

Finder get surface => find.byKey(const ValueKey('signature-drawing-surface'));
Finder get ink => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SignaturePainter);
SignaturePainter painter(WidgetTester t) => t.widget<CustomPaint>(ink).painter! as SignaturePainter;

void main() {
  Future<void> open(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: SignatureCapturePage(initialSignerName: '検証記入者')));
    await t.pumpAndSettle();
  }

  for (final size in [const Size(390, 844), const Size(768, 1024)]) {
    testWidgets('portrait $size shows directions and cannot add ink', (t) async {
      await open(t, size);
      expect(find.text('横向きにしてサインしてください'), findsOneWidget);
      for (final mark in ['↑ 上', '下 ↓', '← 左', '右 →']) {
        expect(find.text(mark), findsOneWidget);
      }
      expect(surface, findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('サインを確定'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  for (final size in [const Size(844, 390), const Size(1024, 768)]) {
    testWidgets('landscape $size removes all guidance before drawing', (t) async {
      await open(t, size);
      expect(find.byType(SignatureOrientationGuide), findsNothing);
      expect(t.widget<GestureDetector>(surface).onPanStart, isNotNull);
      await t.dragFrom(t.getCenter(surface), const Offset(60, 20));
      await t.pump();
      expect(painter(t).strokes, isNotEmpty);
      await t.tap(find.text('消去'));
      await t.pump();
      expect(painter(t).strokes, isEmpty);
      expect(find.byType(SignatureOrientationGuide), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('portrait pauses ink, landscape resumes a new stroke with saved dimensions', (t) async {
    await open(t, const Size(844, 390));
    await t.dragFrom(t.getCenter(surface), const Offset(60, 20));
    await t.pump();
    final before = jsonEncode(SignatureResult(signerName: '検証', strokes: painter(t).strokes,
      canvasSize: painter(t).canvasSize).toJson());
    final capture = painter(t).canvasSize!;
    t.view.physicalSize = const Size(390, 844);
    await t.pumpAndSettle();
    expect(find.byType(SignatureOrientationGuide), findsOneWidget);
    expect(surface, findsNothing);
    expect(find.byType(TextField), findsNothing);
    t.view.physicalSize = const Size(844, 390);
    await t.pumpAndSettle();
    expect(find.byType(SignatureOrientationGuide), findsNothing);
    expect(jsonEncode(SignatureResult(signerName: '検証', strokes: painter(t).strokes,
      canvasSize: painter(t).canvasSize).toJson()), before);
    expect(t.getSize(ink).aspectRatio, closeTo(capture.aspectRatio, .001));
    await t.dragFrom(t.getCenter(surface) - const Offset(20, 20), const Offset(40, 20));
    await t.pump();
    expect(painter(t).strokes.length, 2);
    expect(painter(t).canvasSize, capture);
    expect(t.takeException(), isNull);
  });

  testWidgets('tablet text enlargement keeps portrait guide inside its frame', (t) async {
    t.view.physicalSize = const Size(768, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(size: Size(768, 1024), textScaler: TextScaler.linear(1.5)),
      child: SignatureCapturePage(initialSignerName: '検証'))));
    expect(find.byType(SignatureOrientationGuide), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('saved vector top and right retain direction in contained image', (t) async {
    final capture = SignatureResult(signerName: '検証', canvasSize: const Size(800, 200),
      strokes: [[const Offset(.1, .2), const Offset(.9, .2), const Offset(.9, .8)]]);
    final saved = jsonDecode(jsonEncode({'strokes': capture.toJson()}));
    expect(SignatureResult.sizeFromJson(saved), const Size(800, 200));
    final strokes = SignatureResult.fromJson(saved);
    final rgba = await t.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      SignaturePainter(strokes: strokes, canvasSize: SignatureResult.sizeFromJson(saved))
        .paint(canvas, const Size(300, 150));
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 150);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();picture.dispose();return bytes!;
    });
    int red(int x, int y) => rgba!.getUint8((y * 300 + x) * 4);
    expect(red(150, 52), lessThan(80), reason: 'top horizontal stroke');
    expect(red(270, 75), lessThan(80), reason: 'right vertical stroke');
    expect(red(30, 75), greaterThan(240), reason: 'no mirrored left stroke');
    expect(red(150, 97), greaterThan(240), reason: 'no inverted bottom stroke');
    expect(saved['strokes'][0][0]['x'], .1);
  });
}
