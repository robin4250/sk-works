import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';

void main() {
  testWidgets('interrupted pointer strokes cannot return a confirmed manager signature', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SignatureResult? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        result = await Navigator.of(context).push<SignatureResult>(MaterialPageRoute(
          builder: (_) => const SignatureCapturePage(initialSignerName: 'Synthetic manager')));
      }, child: const Text('Open signature'))))));
    await tester.tap(find.text('Open signature')); await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey('signature-drawing-surface'));
    // An OS gesture can begin and then end/cancel without any motion update.
    // Deliver that existing widget callback sequence twice, as in the two-dot
    // saved original, without manufacturing a line between separate strokes.
    for (final point in [const Offset(100, 40), const Offset(160, 70)]) {
      final gesture = tester.widget<GestureDetector>(surface);
      gesture.onPanStart!(DragStartDetails(localPosition: point));
      gesture.onPanCancel!();
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('signature-confirm-corner')));
    await tester.pumpAndSettle();
    if (result != null) {
      // Synthetic evidence marker only: startup/analyzer failures cannot emit it.
      // ignore: avoid_print
      print('POINT_ONLY_SIGNATURE_ACCEPTED');
    }
    expect(result, isNull, reason: 'No visible stroke must never be confirmed');
    expect(find.byType(SignatureCapturePage), findsOneWidget);
  });
}
