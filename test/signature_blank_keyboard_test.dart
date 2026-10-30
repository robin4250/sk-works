import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

const _surfaceKey = ValueKey('signature-drawing-surface');
const _confirmKey = ValueKey('signature-confirm-corner');
Finder get _surface => find.byKey(_surfaceKey);
Finder get _confirm => find.byKey(_confirmKey);
SignaturePainter _painter(WidgetTester tester) => tester.widget<CustomPaint>(
  find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is SignaturePainter)).painter! as SignaturePainter;

Future<void> _open(WidgetTester tester, void Function(SignatureResult?) completed,
    {String name = '責任者本人', String title = '責任者サイン'}) async {
  tester.view.physicalSize = const Size(844, 390);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.viewPadding = const FakeViewPadding(bottom: 21);
  tester.view.padding = const FakeViewPadding(bottom: 21);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
    body: TextButton(onPressed: () async {
      completed(await Navigator.of(context).push<SignatureResult>(MaterialPageRoute(
        builder: (_) => SignatureCapturePage(initialSignerName: name, title: title))));
    }, child: const Text('サインを開く'))))));
  await tester.tap(find.text('サインを開く'));
  await tester.pumpAndSettle();
}

void main() {
  test('no visible per-stroke segment rejects blank, isolated dots, repeated points and clipped/nonfinite values', () {
    for (final strokes in <List<List<Offset>>>[
      [], [[]], [[const Offset(.2, .3)]],
      [[const Offset(.2, .3)], [const Offset(.7, .8)]],
      [[const Offset(.2, .3), const Offset(.2, .3)]],
      [[const Offset(.2, .3), const Offset(.20001, .3)]],
      [[const Offset(-.1, .3), const Offset(.7, .8)]],
      [[const Offset(.1, .3), Offset(double.nan, .8)]],
    ]) { expect(signatureHasDrawableInk(strokes), isFalse); }
    expect(signatureHasDrawableInk([[const Offset(.2, .3), const Offset(.4, .5)]]), isTrue);
    expect(signatureHasDrawableInk([[const Offset(.2, .3), const Offset(.4, .5)]],
      canvasSize: const Size(0, 0)), isFalse);
  });

  testWidgets('interrupted pan without motion cannot confirm a point-only signature', (tester) async {
    var completed = false;
    await _open(tester, (_) { completed = true; });
    final gesture = tester.widget<GestureDetector>(_surface);
    gesture.onPanStart!(DragStartDetails(localPosition: Offset(100, 40)));
    gesture.onPanCancel!();
    await tester.pump();
    expect(_painter(tester).strokes.expand((stroke) => stroke), isNotEmpty);
    expect(signatureHasDrawableInk(_painter(tester).strokes), isFalse);
    await tester.tap(_confirm); await tester.pump();
    expect(completed, isFalse);
    expect(find.byType(SignatureCapturePage), findsOneWidget);
    expect(find.text('サインを入力してください'), findsOneWidget);
  });

  for (final title in ['報告者サイン', '責任者サイン']) {
    testWidgets('$title name keyboard keeps canvas size and confirm only ends name input', (tester) async {
      var completed = false;
      await _open(tester, (_) { completed = true; }, name: '', title: title);
      final before = tester.getRect(_surface);
      await tester.enterText(find.byType(TextField), '入力した本人');
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.view.padding = const FakeViewPadding();
      await tester.pump();
      expect(tester.getRect(_surface), before);
      expect(find.byKey(const ValueKey('signature-name-done')), findsOneWidget);
      await tester.tap(_confirm); await tester.pump();
      expect(completed, isFalse);
      expect(_painter(tester).strokes, isEmpty);
      tester.view.viewInsets = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding(bottom: 21);
      await tester.pumpAndSettle();
      await tester.tap(_confirm); await tester.pump();
      expect(completed, isFalse);
      expect(find.text('サインを入力してください'), findsOneWidget);
    });
  }

  testWidgets('canvas gesture used to dismiss name keyboard never becomes ink', (tester) async {
    var completed = false;
    await _open(tester, (_) { completed = true; });
    await tester.enterText(find.byType(TextField), '変更した本人');
    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.view.padding = const FakeViewPadding();
    await tester.pump();
    await tester.dragFrom(tester.getCenter(_surface), const Offset(70, 20));
    await tester.pump();
    expect(_painter(tester).strokes, isEmpty);
    tester.view.viewInsets = const FakeViewPadding();
      tester.view.padding = const FakeViewPadding(bottom: 21);
    await tester.pumpAndSettle();
    await tester.tap(_confirm); await tester.pump();
    expect(completed, isFalse);
  });

  testWidgets('clearing real ink rejects confirmation and a new intentional signature succeeds', (tester) async {
    SignatureResult? result;
    await _open(tester, (value) { result = value; });
    await tester.dragFrom(tester.getCenter(_surface), const Offset(70, 20));
    await tester.pump();
    expect(signatureHasDrawableInk(_painter(tester).strokes), isTrue);
    await tester.tap(find.text('消去')); await tester.pump();
    await tester.tap(_confirm); await tester.pump();
    expect(result, isNull);
    expect(_painter(tester).strokes, isEmpty);
    await tester.dragFrom(tester.getCenter(_surface), const Offset(70, 20));
    await tester.pump();
    await tester.tap(_confirm); await tester.pumpAndSettle();
    expect(result?.hasDrawableInk, isTrue);
    expect(find.byType(SignatureCapturePage), findsNothing);
  });

  testWidgets('editing a name after real ink still requires a separate signature confirmation', (tester) async {
    SignatureResult? result;
    await _open(tester, (value) { result = value; });
    await tester.dragFrom(tester.getCenter(_surface), const Offset(70, 20)); await tester.pump();
    await tester.enterText(find.byType(TextField), '本人が訂正した氏名'); await tester.pump();
    await tester.tap(_confirm); await tester.pump();
    expect(result, isNull);
    await tester.tap(_confirm); await tester.pumpAndSettle();
    expect(result?.signerName, '本人が訂正した氏名');
    expect(result?.hasDrawableInk, isTrue);
  });

  testWidgets('legacy point evidence remains visible as a dot but cannot validate as a signature', (tester) async {
    const strokes = [[Offset(.5, .5)]];
    expect(signatureHasDrawableInk(strokes), isFalse);
    final rgba = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      const SignaturePainter(strokes: strokes).paint(canvas, const Size(200, 100));
      final picture = recorder.endRecording(); final image = await picture.toImage(200, 100);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose(); picture.dispose(); return bytes!;
    });
    expect(rgba!.getUint8((50 * 200 + 100) * 4), lessThan(80));
  });
}
