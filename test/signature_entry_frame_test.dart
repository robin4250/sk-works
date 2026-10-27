import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sk_works/features/daily_reports/signature_capture_page.dart';
import 'package:sk_works/features/daily_reports/signature_entry_frame.dart';

void main() {
  for (final role in ['報告者', '責任者']) {
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      testWidgets('$role $size has a non-drawing entry and one-tap fullscreen return', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        SignatureResult? saved;
        await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: ListTile(
            subtitle: SignatureEntryFrame(role: role, signerName: '試験記入者'),
            onTap: () async {
              saved = await Navigator.of(context).push<SignatureResult>(
                MaterialPageRoute(fullscreenDialog: true, builder: (_) =>
                  SignatureCapturePage(title: '$roleサイン', initialSignerName: '試験記入者',
                    submitLabel: '確定')));
            },
          ),
        ))));
        expect(find.byKey(const ValueKey('signature-drawing-surface')), findsNothing);
        expect(find.text('$role：試験記入者'), findsOneWidget);
        expect(t.widget<RotatedBox>(find.byKey(const ValueKey('signature-entry-turn-guide'))).quarterTurns,
          size.width < size.height ? 1 : 0);
        await t.tap(find.text('横向きでサインしてください'));
        await t.pumpAndSettle();
        t.view.physicalSize = const Size(844, 390);
        await t.pumpAndSettle();
        expect(find.byType(SignatureOrientationGuide), findsNothing);
        final surface = find.byKey(const ValueKey('signature-drawing-surface'));
        expect(surface, findsOneWidget);
        await t.dragFrom(t.getCenter(surface), const Offset(60, 20));
        await t.pump();
        final confirm = find.byKey(const ValueKey('signature-confirm-corner'));
        expect(find.descendant(of: confirm, matching: find.text('確定')), findsOneWidget);
        await t.tap(confirm);
        await t.pumpAndSettle();
        expect(find.byType(SignatureCapturePage), findsNothing);
        expect(find.byType(SignatureEntryFrame), findsOneWidget);
        expect(saved?.signerName, '試験記入者');
        expect(saved?.strokes, isNotEmpty);
        expect(saved!.canvasSize!.width, greaterThan(saved!.canvasSize!.height));
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('large text keeps rotated entry guidance inside a small frame', (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
      child: Scaffold(body: ListTile(
        subtitle: SignatureEntryFrame(role: '責任者', signerName: '試験記入者'),
      )),
    )));
    expect(find.text('横向きでサインしてください'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
